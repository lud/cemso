defmodule Cemso.Solver do
  alias Cemso.IgnoreFile
  alias Cemso.Utils.TopList
  alias Cemso.WordsTable
  require Logger
  use GenServer, restart: :transient

  @gen_opts ~w(name timeout debug spawn_opt hibernate_after)a

  # How much similar words to lookup with the slow algorithm
  @slow_n_similar 10
  @n_rand 10

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
      # test list only for fast
      test_list: state.init_list,
      # init list only for slow
      init_list:
        case state.init_list do
          [] -> :used
          list -> list
        end,
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
    defstruct word: nil, score: nil, expanded: 0, from: [], recent: true
  end

  # defp loop(%{fast: false, test_list: []} = solver) do
  #   # Take first word not expanded yet and select similar words

  #   print_scores(solver)

  #   solver.score_list
  #   |> Stream.filter(fn %Attempt{expanded: is?} -> not is? end)
  #   |> Enum.take(1)
  #   |> case do
  #     [] ->
  #       solver
  #       |> with_new_random_test_list()
  #       |> with_empty_score_list()
  #       |> loop()

  #     [%Attempt{word: word, expanded: false} = top] ->

  #       Logger.info("Selecting #{n_similar} similar words to #{inspect(word)}")
  #       new_test_list = similar_words(top, @slow_n_similar, solver.closed_list)

  #       new_score_list =
  #         solver.score_list
  #         |> TopList.drop(top)
  #         |> TopList.put(%Attempt{top | expanded: true})

  #       loop(%{solver | test_list: new_test_list, score_list: new_score_list})
  #   end
  # end

  defp loop(%{fast: false} = solver) do
    print_scores(solver)

    solver = unflag_recent_attempts(solver)

    n_similar = @slow_n_similar

    {expanded_from, test_list_pool, solver} =
      solver.score_list
      |> Stream.filter(fn %Attempt{expanded: exp} -> exp < @slow_n_similar end)
      |> Enum.take(1)
      |> case do
        [] when is_list(solver.init_list) ->
          {:init, solver.init_list, %{solver | init_list: :used}}

        [] ->
          {:random, select_random_words(solver.closed_list), solver}

        [%Attempt{word: word, expanded: exp} = top] when exp < @slow_n_similar ->
          # Always reselect a full batch of similar words, so we do not use:
          #
          #     n_similar = @slow_n_similar - top.expanded
          #
          # This avoids walking the full words table just to select 1 word that
          # will be unknown, multiple times. We can overshoot the :expanded number

          Logger.info([
            "Selecting #{n_similar} similar words to ",
            IO.ANSI.bright(),
            word,
            IO.ANSI.normal()
          ])

          # Take 10 times the expected number of similar words, so we have room
          # for score failures
          smilars =
            case similar_words(top, (n_similar * 10), solver.closed_list) do
              [] -> exit(:no_more_words)
              list -> list
            end


          {top, smilars, solver}
      end

    stop_ref = make_ref()

    {valid_count, new_attempts, closed_list} =
      test_list_pool
      # We want to get no more than `n_similar` scores but we want to let
      # unscorable words continue downstream so we can add them to the closed
      # list.
      #
      # We cannot just reduce over everything because we want to introduce a
      # `Stream.take(stream, n_similar)` in between.
      |> Stream.map(fn attempt ->
        case get_score(solver, attempt) do
          {:ok, score} ->
            {:score, attempt, score}

          {:error, :cemantix_unknown} ->
            Logger.warning("Unknown word #{attempt.word}")
            :ok = IgnoreFile.add(solver.ignore_file, attempt.word)
            {:noscore, attempt}

          {:error, message} ->
            Logger.error(message)
            {:noscore, attempt}
        end
      end)
      # take `n_similar` successful attempts. They may be less than that but in
      # this case the stream will end normally.
      |> Stream.transform(0, fn
        {:score, _, _} = item, scored_count when scored_count == n_similar - 1 ->
          {[item, stop_ref], nil}

        {:score, _, _} = item, scored_count ->
          {[item], scored_count + 1}

        {:noscore, _} = item, scored_count ->
          {[item], scored_count}
      end)
      |> Stream.take_while(&(&1 != stop_ref))
      # finally handle our attempts, computing what is right for good and bad
      # attempts.
      |> Enum.reduce({_valid_count = 0, _valids = [], solver.closed_list}, fn
        {:noscore, attempt}, {valid_count, valids, closed_list} ->
          closed_list = [attempt.word | closed_list]
          {valid_count, valids, closed_list}

        {:score, attempt, score}, {valid_count, valids, closed_list} ->
          closed_list = [attempt.word | closed_list]
          attempt = %Attempt{attempt | score: score}
          {valid_count + 1, [attempt | valids], closed_list}
      end)

    score_list =
      case expanded_from do
        :random ->
          empty_score_list(false = solver.fast)

        :init ->
          solver.score_list

        parent_attempt ->
          solver.score_list
          |> TopList.drop(parent_attempt)
          |> TopList.put(Map.update!(parent_attempt, :expanded, &(&1 + valid_count)))
      end

    score_list = Enum.reduce(new_attempts, score_list, &TopList.put(&2, &1))

    solver = %{solver | score_list: score_list, closed_list: closed_list}

    case check_success(solver) do
      :continue -> loop(solver)
      :success -> :ok
    end
  end

  defp loop(%{fast: true, test_list: []} = solver) do
    # Take all words from list and select words at range

    print_scores(solver)

    solver = unflag_recent_attempts(solver)

    solver.score_list
    |> TopList.to_list(&{&1.word, &1.score})
    |> case do
      [] ->
        solver
        |> with_new_random_test_list()
        |> with_empty_score_list()
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
        Logger.warning("Unknown word #{head_word}")
        :ok = IgnoreFile.add(solver.ignore_file, head_word)
        loop(%{solver | test_list: t})

      {:error, message} ->
        Logger.error(message)
        loop(solver)
    end
  end

  defp check_success(solver) do
    case Enum.at(solver.score_list, 0) do
      %{score: score} = attempt when score > 0.9999 ->
        print_scores(solver)
        show_success(attempt)
        :success

      _ ->
        :continue
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

  defp with_new_random_test_list(solver) do
    new_test_list = select_random_words(solver.closed_list)

    if [] != solver.closed_list do
      Logger.warning("Resetting scores list")
    end

    %{solver | test_list: new_test_list}
  end

  defp with_empty_score_list(solver) do
    %{solver | score_list: empty_score_list(solver.fast)}
  end

  defp compare_score(%Attempt{score: a}, %Attempt{score: b}) do
    a > b
  end

  defp select_random_words(closed_list) do
    Logger.info("Selecting #{@n_rand} random words")

    case random_words(@n_rand, closed_list) do
      [] ->
        Logger.error("Exhausted all random words")
        System.stop()
        Process.sleep(:infinity)

      list ->
        list
    end
    |> from_random()
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
    Logger.info(["Scores:\n", format_scores(solver)])
  end

  defp format_scores(solver) do
    TopList.to_list(solver.score_list, fn attempt ->
      %Attempt{
        word: word,
        score: score,
        expanded: exp,
        from: parent_words,
        recent: recent?
      } = attempt

      str_score = score |> to_string() |> String.slice(0..4) |> String.pad_trailing(5, "0")
      expanded = if(exp >= @slow_n_similar, do: "!", else: " ")
      word = String.slice(word, 0..20) |> String.pad_trailing(20)

      word =
        if recent?,
          do: [IO.ANSI.bright(), word, IO.ANSI.normal()],
          else: word

      sep = " <- "

      max_trail = 4

      parents =
        if length(parent_words) > max_trail do
          [Enum.take(parent_words, max_trail) |> Enum.intersperse(sep), sep, "..."]
        else
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
    Enum.map(words, &%Attempt{word: &1, expanded: 0, from: ["--init"], score: nil})
  end

  defp from_random(words) do
    Enum.map(words, &%Attempt{word: &1, expanded: 0, from: ["*"], score: nil})
  end

  defp from_parent(words, %Attempt{word: parent_word, from: parent_from}) do
    Enum.map(
      words,
      &%Attempt{word: &1, expanded: 0, from: [parent_word | parent_from], score: nil}
    )
  end

  defp from_range(words) do
    Enum.map(
      words,
      &%Attempt{word: &1, expanded: 0, from: ["%"], score: nil}
    )
  end

  defp unflag_recent_attempts(solver) do
    Map.update!(solver, :score_list, fn list ->
      TopList.map(list, &%Attempt{&1 | recent: false})
    end)
  end
end
