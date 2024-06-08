defmodule Cemso.WordsTable do
  alias Cemso.IgnoreFile
  alias Cemso.Utils.TopList
  use GenServer
  require Logger
  import Nx.Defn

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

    fun = fn {word, dims}, tl ->
      if word in ignore_list do
        tl
      else
        similarity = similarity(dimensions, dims)
        TopList.put(tl, {similarity, word})
      end
    end

    toplist = :ets.foldl(fun, TopList.new(n, fn {a, _}, {b, _} -> a > b end), @tab)

    TopList.to_list(toplist, fn {_, word} -> word end)
  end

  def get_word(word) do
    [{^word, _dimensions} = found] = :ets.lookup(@tab, word)
    found
  end

  # def distance(dims_a, dims_b),
  #   do: distance(dims_a, dims_b, 0)

  # defp distance([ha | ta], [hb | tb], sum),
  #   do: distance(ta, tb, sum + :math.pow(ha - hb, 2))

  # defp distance([], [], sum),
  #   do: :math.sqrt(sum)

  def similarity(a, b) do
    ret =
      cosine_similarity(a, b)
      |> Nx.to_number()

    ret
  end

  defnp cosine_similarity(a, b) do
    Nx.dot(a, b) / (Nx.LinAlg.norm(a) * Nx.LinAlg.norm(b))
  end

  @impl true
  def init(opts) do
    source = Keyword.fetch!(opts, :source)
    ignore_file = Keyword.fetch!(opts, :ignore_file)
    Logger.info("words table initializing")
    tab = :ets.new(@tab, [:ordered_set, :public, :named_table])

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
            # false -> true = :ets.insert(tab, {word, dimensions})
            false -> true = :ets.insert(tab, {word, Nx.tensor(dimensions)})
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
