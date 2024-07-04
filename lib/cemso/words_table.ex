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

    tl =
      parallel_map(
        fn {word, dims} ->
          similarity = similarity(dimensions, dims)
          {similarity, word}
        end,
        fn {a, _}, {b, _} -> a > b end,
        n,
        ignore_list
      )

    TopList.to_list(tl, fn {_, word} -> word end)
  end

  # Select words who have a similarity close to best_similarity
  def select_at_range(word, best_similarity, n, ignore_list) do
    [{^word, dimensions}] = :ets.lookup(@tab, word)

    tl =
      parallel_map(
        fn {word, dims} ->
          similarity = similarity(dimensions, dims)
          proximity = abs(similarity - best_similarity)
          {proximity, word}
        end,
        fn {a, _}, {b, _} -> a < b end,
        n,
        ignore_list
      )

    TopList.to_list(tl, fn {_, word} -> word end)
  end

  # Select words who have, for each word, a similar reciprocal similarity
  def select_at_range_multi(words_scores, n, ignore_list) do
    targets =
      Enum.map(words_scores, fn {word, score} ->
        [{^word, dimensions}] = :ets.lookup(@tab, word)
        {word, dimensions, score}
      end)

    target_count = length(words_scores)

    tl =
      parallel_map(
        fn {word, dims} ->
          range_proximity_sum =
            Enum.reduce(targets, 0, fn {_t_word, t_dimensions, t_score}, sum ->
              similarity = similarity(t_dimensions, dims)
              range_proxymity = abs(similarity - t_score)

              sum + range_proxymity
            end)

          {range_proximity_sum / target_count, word}
        end,
        # We want the minimum proximity
        fn {a, _}, {b, _} -> a < b end,
        n,
        ignore_list
      )

    TopList.to_list(tl, fn {_, word} -> word end)
  end

  defp parallel_map(mapper, comparator, n, ignore_list) do
    # Start with the first key in the table.
    :ets.first(@tab)

    # For each key in the table we will return the tuple of word+dimensions,
    # and the next key. Stop when the key is $end_of_table.
    |> Stream.unfold(fn
      :"$end_of_table" ->
        nil

      prev ->
        [{^prev, _} = elem] = :ets.lookup(@tab, prev)
        {elem, :ets.next(@tab, prev)}
    end)

    # Ignore the words from the ignore list. We do not do that in the async
    # stream to avoid copying the list on each async task.
    |> Stream.filter(fn {word, _} -> word not in ignore_list end)

    # Split the stream in chunks of N words to send to an async task.
    |> Stream.chunk_every(100)

    # For each chunk, start an async task and apply the mapper to the
    # word+dimensions tuple.
    |> Task.async_stream(
      fn words ->
        Enum.map(words, mapper)
      end,
      timeout: :infinity,
      ordered: false
    )

    # Unwrap the task
    |> Stream.flat_map(fn {:ok, list} -> list end)

    # Reduce to the top list and return it
    |> Enum.reduce(TopList.new(n, comparator), fn mapped_result, tl ->
      TopList.put(tl, mapped_result)
    end)
  end

  def get_word(word) do
    [{^word, _dimensions} = found] = :ets.lookup(@tab, word)
    found
  end

  # Helper to check values from the shell
  def words_similarity(word_a, word_b) do
    [{^word_a, dimensions_a}] = :ets.lookup(@tab, word_a)
    [{^word_b, dimensions_b}] = :ets.lookup(@tab, word_b)
    similarity(dimensions_a, dimensions_b)
  end

  # Shell helper
  def lookup_word(word) do
    :ets.lookup(@tab, word)
  end

  def similarity(dimensions_a, dimensions_b) do
    cosine_similarity(dimensions_a, dimensions_b)
  end

  def cosine_similarity(dimensions_a, dimensions_b) do
    dot(normalize(dimensions_a), normalize(dimensions_b))
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

    ignored_count =
      Cemso.ConvertVec.bin2txt(input_path, :initial, fn
        :wordcount, wordcount, :initial ->
          Logger.info("Loading #{wordcount} words into memory")
          _ignored_count = 0

        :dimensions, _dimensions, ignored_count ->
          ignored_count

        :word, {word, dimensions}, ignored_count ->
          case MapSet.member?(ignored_words, word) do
            false ->
              true = :ets.insert(tab, {word, dimensions})
              ignored_count

            true ->
              # Logger.debug("Ignored word #{inspect(word)}")
              ignored_count + 1
          end
      end)

    Logger.info("Loading words completed, ignored #{ignored_count} words")
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
