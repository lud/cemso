defmodule Cemso.WordsTable do
  alias Cemso.IgnoreFile
  alias Cemso.Utils.TopList
  use GenServer
  require Logger

  @tab __MODULE__
  @gen_opts ~w(name timeout debug spawn_opt hibernate_after)a

  def start_link(opts) do
    {gen_opts, opts} = Keyword.split(opts, @gen_opts)
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  def subscribe(server) do
    GenServer.call(server, {:subscribe, self()})
  end

  def select_random(n, ignore_list) do
    # generate a random number for each word and select the N smallest ones

    fun = fn {word, _dims}, tl ->
      if word in ignore_list do
        tl
      else
        TopList.put(tl, {:rand.uniform(), word})
      end
    end

    toplist = :ets.foldl(fun, TopList.new(n, &Kernel.</2), @tab)

    TopList.to_list(toplist, fn {_, word} -> word end)
  end

  def select_similar(word, n, ignore_list) do
    [{^word, dimensions}] = :ets.lookup(@tab, word)

    Stream.unfold(:ets.first(@tab), fn
      :"$end_of_table" ->
        nil

      prev ->
        [{^prev, _} = elem] = :ets.lookup(@tab, prev)
        {elem, :ets.next(@tab, prev)}
    end)
    |> Stream.filter(fn {word, _} -> word not in ignore_list end)
    |> Stream.chunk_every(100)
    |> Task.async_stream(
      fn wordslist ->
        Enum.map(wordslist, fn {word, dims} ->
          similarity = similarity(dimensions, dims)
          {word, similarity}
        end)
      end,
      timeout: :infinity,
      ordered: false
    )
    |> Stream.flat_map(fn {:ok, list} -> list end)
    |> Enum.reduce(TopList.new(n, fn {a, _}, {b, _} -> a > b end), fn
      {word, similarity}, tl -> TopList.put(tl, {similarity, word})
    end)
    |> TopList.to_list(fn {_, word} -> word end)
  end

  def get_word(word) do
    [{^word, _dimensions} = found] = :ets.lookup(@tab, word)
    found
  end

  def similarity(a, b) do
    cosine_similarity(a, b)
  end

  def cosine_similarity(a, b) do
    dot(normalize(a), normalize(b))
  end

  def dot(a, b) do
    Enum.zip_reduce(a, b, 0, fn ai, bi, sum -> sum + ai * bi end)
  end

  def normalize(a) do
    norm = Enum.reduce(a, 0, fn ai, sum -> sum + ai * ai end) |> :math.sqrt()
    Enum.map(a, fn ai -> ai / norm end)
  end

  @impl true
  def init(opts) do
    source = Keyword.fetch!(opts, :source)
    ignore_file = Keyword.fetch!(opts, :ignore_file)
    Logger.info("words table initializing")
    tab = :ets.new(@tab, [:ordered_set, :public, :named_table, {:read_concurrency, true}])

    state = %{
      source: source,
      status: :init,
      load_ref: nil,
      tab: tab,
      subscribers: [],
      ignore_file: ignore_file
    }

    {:ok, state, {:continue, :load_table}}
  end

  @impl true
  def handle_continue(:load_table, %{status: :init} = state) do
    ignored_words = state.ignore_file |> IgnoreFile.to_list() |> MapSet.new()
    load_ref = Task.async(fn -> do_load(state.source, state.tab, ignored_words) end).ref
    {:noreply, %{state | load_ref: load_ref}}
  end

  @impl true
  def handle_call({:subscribe, pid}, _from, state) do
    state = %{state | subscribers: [pid | state.subscribers]}
    {:reply, :ok, maybe_publish(state)}
  end

  @impl true
  def handle_info({load_ref, :ok}, %{load_ref: load_ref} = state) do
    state = %{state | load_ref: nil, status: :loaded}
    true = Process.demonitor(load_ref, [:flush])
    {:noreply, maybe_publish(state)}
  end

  defp do_load(source, tab, ignored_words) do
    Cemso.SourceData.download_source(source)
    input_path = Cemso.SourceData.download_path(source)

    :ok =
      Cemso.ConvertVec.bin2txt(input_path, :initial, fn
        :wordcount, wordcount, :initial ->
          Logger.info("Loading #{wordcount} words into memory")

        :dimensions, _dimensions, acc ->
          acc

        :word, {word, dimensions}, acc ->
          case MapSet.member?(ignored_words, word) do
            true -> Logger.debug("Ignored word #{inspect(word)}")
            false -> true = :ets.insert(tab, {word, dimensions})
          end

          acc
      end)

    Logger.info("Loading words completed")
    :ok
  end

  defp maybe_publish(%{status: :init} = state), do: state

  defp maybe_publish(%{status: :loaded} = state) do
    Enum.each(state.subscribers, fn pid ->
      send(pid, {__MODULE__, :loaded})
    end)

    %{state | subscribers: []}
  end
end
