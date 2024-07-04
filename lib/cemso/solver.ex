defmodule Cemso.Solver do
  alias Cemso.IgnoreFile
  alias Cemso.Utils.TopList
  alias Cemso.WordsTable
  require Logger
  use GenServer, restart: :transient

  @gen_opts ~w(name timeout debug spawn_opt hibernate_after)a

  def start_link(opts) do
    Logger.info("Solver initialized")
    {gen_opts, opts} = Keyword.split(opts, @gen_opts)
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @impl true
  def init(opts) do
    loader = Keyword.fetch!(opts, :loader)
    ignore_file = Keyword.fetch!(opts, :ignore_file)
    score_adapter = Keyword.fetch!(opts, :score_adapter)
    fast = Keyword.get(opts, :fast, false)
    init_list = opts |> Keyword.fetch!(:init_list) |> from_opts()
    :ok = WordsTable.subscribe(loader)

    {:ok,
     %{ignore_file: ignore_file, score_adapter: score_adapter, init_list: init_list, fast: fast}}
  end

  @impl true
  def handle_info({WordsTable, :loaded}, state) do
    Logger.info("Solver starting to solve")
    solve(state)
    {:stop, :normal, state}
  end

  defp solve(state) do
    solver = %{
      test_list: state.init_list,
      fast: state.fast,
      score_list: empty_score_list(state.fast),
      closed_list: [],
      ignore_file: state.ignore_file,
      score_adapter: state.score_adapter
    }

    loop(solver)
  end

  defp empty_score_list(true = _fast) do
    TopList.new(5, &compare_score/2)
  end

  defp empty_score_list(false = _fast) do
    TopList.new(20, &compare_score/2)
  end

  defmodule Attempt do
    defstruct word: nil, score: nil, expanded?: false, from: []
  end

  defp loop(%{fast: false, test_list: []} = solver) do
    # Take first word not expanded yet and select similar words

    print_scores(solver)

    TopList.to_list(solver.score_list)
    |> Stream.filter(fn %Attempt{expanded?: is?} -> not is? end)
    |> Enum.take(1)
    |> case do
      [] ->
        solver
        |> reset_test_list()
        |> reset_score_list()
        |> loop()

      [%Attempt{word: word, expanded?: false} = top] ->
        n_similar = 10
        Logger.info("Selecting #{n_similar} similar words to #{inspect(word)}")
        new_test_list = similar_words(top, n_similar, solver.closed_list)

        new_score_list =
          solver.score_list
          |> TopList.drop(top)
          |> TopList.put(%Attempt{top | expanded?: true})

        loop(%{solver | test_list: new_test_list, score_list: new_score_list})
    end
  end

  defp loop(%{fast: true, test_list: []} = solver) do
    # Take all words from list and select words at range

    print_scores(solver)

    solver.score_list
    |> TopList.to_list(&{&1.word, &1.score})
    |> case do
      [] ->
        solver
        |> reset_test_list()
        |> reset_score_list()
        |> loop()

      all_known_scored_words ->
        n_at_range = 10
        Logger.info("Selecting #{n_at_range} words at best range")

        new_test_list =
          words_at_range_multi(all_known_scored_words, n_at_range, solver.closed_list)

        loop(%{solver | test_list: new_test_list})
    end
  end

  defp loop(%{test_list: [%Attempt{word: head_word} = h | t]} = solver) do
    # We have items in the test list. We score them one by one
    %{score_list: score_list, closed_list: closed_list} = solver

    # we will not allow this word in the test list again
    solver = %{solver | closed_list: [head_word | closed_list]}

    case get_score(solver, h) do
      # If we get a score we add that to the score list and remove from the test list
      {:ok, score} ->
        attempt = %Attempt{h | score: score}
        score_list = TopList.put(score_list, attempt)
        solver = %{solver | test_list: t, score_list: score_list}

        # Local simulator may give score of 0.9999 instead of 1
        if score > 0.9999 do
          print_scores(solver)
          show_success(attempt)

          :ok
        else
          loop(solver)
        end

      # If the word is unknown we only remove from the test list
      {:error, :cemantix_unknown} ->
        Logger.warning("Unknow word #{head_word}")
        :ok = IgnoreFile.add(solver.ignore_file, head_word)
        loop(%{solver | test_list: t})

      {:error, message} ->
        Logger.error(message)
        loop(solver)
    end
  end

  defp show_success(attempt) do
    %Attempt{word: word, score: score, from: from} = attempt

    Logger.info(
      [
        "Found word for today: ",
        IO.ANSI.bright(),
        word,
        IO.ANSI.normal(),
        " with score of #{score}"
      ],
      ansi_color: :light_green
    )

    Logger.info(
      [
        "Path: ",
        from |> :lists.reverse() |> Enum.map(&[&1, " -> "]),
        IO.ANSI.bright(),
        word,
        IO.ANSI.normal()
      ],
      ansi_color: :light_green
    )
  end

  defp reset_test_list(solver) do
    n_rand = 10
    Logger.info("Selecting #{n_rand} random words")

    new_test_list =
      case random_words(n_rand, solver.closed_list) do
        [] ->
          Logger.error("Exhausted all random words")
          System.stop()
          Process.sleep(:infinity)

        list ->
          list
      end
      |> from_random()

    if [] != solver.closed_list do
      Logger.warning("Resetting scores list")
    end

    %{solver | test_list: new_test_list}
  end

  defp reset_score_list(solver) do
    %{solver | score_list: empty_score_list(solver.fast)}
  end

  defp compare_score(%Attempt{score: a}, %Attempt{score: b}) do
    a > b
  end

  defp random_words(n_rand, known_words) do
    WordsTable.select_random(n_rand, known_words)
  end

  # defp words_at_range(parent, n_similar, known_words) do
  #   selected = WordsTable.select_at_range(parent.word, parent.score, n_similar, known_words)
  #   from_parent(selected, parent)
  # end

  defp words_at_range_multi(scored_words, n_at_range, known_words) do
    selected = WordsTable.select_at_range_multi(scored_words, n_at_range, known_words)

    from_range(selected)
  end

  defp similar_words(parent, n_similar, known_words) do
    selected = WordsTable.select_similar(parent.word, n_similar, known_words)
    from_parent(selected, parent)
  end

  defp get_score(solver, %Attempt{word: word} = _test_attempt) do
    {mod, args} = solver.score_adapter

    apply(mod, :get_score, [word | args])
  end

  defp print_scores(solver) do
    Logger.flush()
    Logger.info(["Scores:\n", format_scores(solver)])
  end

  defp format_scores(solver) do
    TopList.to_list(solver.score_list, fn %Attempt{
                                            word: word,
                                            score: score,
                                            expanded?: e?,
                                            from: parent_words
                                          } ->
      str_score = score |> to_string() |> String.slice(0..4) |> String.pad_trailing(5, "0")
      expanded = if(e?, do: "!", else: " ")
      word = String.slice(word, 0..20) |> String.pad_trailing(20)
      sep = " <- "

      parents =
        case parent_words do
          [a, b, c, d, e, _ | _] ->
            [a, sep, b, sep, c, sep, d, sep, e, sep, "..."]

          _ ->
            Enum.intersperse(parent_words, sep)
        end

      [score_emoji(score), "  ", str_score, " ", expanded, " ", word, sep, parents, "\n"]
    end)
  end

  defp score_emoji(score) when score > 0.9999, do: "🥳"
  defp score_emoji(score) when score >= 0.5, do: "😱"
  defp score_emoji(score) when score >= 0.4, do: "🔥"
  defp score_emoji(score) when score >= 0.2, do: "🥵"
  defp score_emoji(score) when score >= 0.1, do: "😎"
  defp score_emoji(score) when score >= 0, do: "🥶"
  defp score_emoji(_), do: "🧊"

  defp from_opts(words) do
    Enum.map(words, &%Attempt{word: &1, expanded?: false, from: ["--init"], score: nil})
  end

  defp from_random(words) do
    Enum.map(words, &%Attempt{word: &1, expanded?: false, from: ["*"], score: nil})
  end

  defp from_parent(words, %Attempt{word: parent_word, from: parent_from}) do
    Enum.map(
      words,
      &%Attempt{word: &1, expanded?: false, from: [parent_word | parent_from], score: nil}
    )
  end

  defp from_range(words) do
    Enum.map(
      words,
      &%Attempt{word: &1, expanded?: false, from: ["%"], score: nil}
    )
  end
end
