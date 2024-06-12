defmodule Cemso.Solver do
  alias Cemso.IgnoreFile
  alias Cemso.Utils.TopList
  alias Cemso.WordsTable
  require Logger
  use GenServer, restart: :transient

  @gen_opts ~w(name timeout debug spawn_opt hibernate_after)a

  @init_test_list []

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
    :ok = WordsTable.subscribe(loader)
    {:ok, %{ignore_file: ignore_file, score_adapter: score_adapter}}
  end

  @impl true
  def handle_info({WordsTable, :loaded}, state) do
    Logger.info("Solver starting to solve")
    solve(state)
    {:stop, :normal, state}
  end

  defp solve(state) do
    solver = %{
      test_list: @init_test_list,
      score_list: empty_score_list(),
      closed_list: [],
      ignore_file: state.ignore_file,
      score_adapter: state.score_adapter
    }

    loop(solver)
  end

  defp empty_score_list do
    TopList.new(20, &compare_score/2)
  end

  defmodule Attempt do
    defstruct word: nil, score: nil, expanded?: false
  end

  defp loop(%{test_list: []} = solver) do
    # Select first word not expanded yet. When none (at init of if exhausted) we
    # will select random words.

    print_scores(solver)

    TopList.to_list(solver.score_list)
    |> Stream.filter(fn %Attempt{expanded?: is?} -> not is? end)
    |> Enum.take(1)
    |> case do
      [] ->
        true =
          TopList.to_list(solver.score_list, fn %{expanded?: e?} -> e? end) |> Enum.all?(& &1)

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

        if [] != solver.closed_list do
          Logger.warning("Resetting scores list")
        end

        loop(%{solver | test_list: new_test_list, score_list: empty_score_list()})

      [%Attempt{word: word, expanded?: false} = top] ->
        n_similar = 10
        Logger.info("Selecting #{n_similar} similar words to #{inspect(word)}")
        new_test_list = similar_words(word, n_similar, solver.closed_list)

        new_score_list =
          solver.score_list
          |> TopList.drop(top)
          |> TopList.put(%Attempt{top | expanded?: true})

        loop(%{solver | test_list: new_test_list, score_list: new_score_list})
    end
  end

  defp loop(%{test_list: [h | t]} = solver) do
    # We have items in the test list. We score them one by one
    %{score_list: score_list, closed_list: closed_list} = solver

    # we will not allow this word in the test list again
    solver = %{solver | closed_list: [h | closed_list]}

    case get_score(solver, h) do
      # If we get a score we add that to the score list and remove from the test list
      {:ok, score} ->
        score_list = TopList.put(score_list, %Attempt{word: h, score: score, expanded?: false})
        solver = %{solver | test_list: t, score_list: score_list}

        # Local simulator may give score of 0.9999 instead of 1
        if score > 0.9999 do
          print_scores(solver)

          Logger.info("Found word for today: #{inspect(h)} with score of #{score}",
            ansi_color: :light_green
          )

          :ok
        else
          loop(solver)
        end

      # If the word is unknown we only remove from the test list
      {:error, :cemantix_unknown} ->
        Logger.warning("Unknow word #{h}")
        :ok = IgnoreFile.add(solver.ignore_file, h)
        loop(%{solver | test_list: t})

      {:error, message} ->
        Logger.error(message)
        loop(solver)
    end
  end

  defp compare_score(%Attempt{score: a}, %Attempt{score: b}) do
    a > b
  end

  defp random_words(n_rand, known_words) do
    WordsTable.select_random(n_rand, known_words)
  end

  defp similar_words(word, n_similar, known_words) do
    WordsTable.select_similar(word, n_similar * 2, known_words)
  end

  defp get_score(solver, word) do
    {mod, args} = solver.score_adapter

    apply(mod, :get_score, [word | args])
  end

  defp print_scores(solver) do
    Logger.flush()
    Logger.info(["Scores:\n", format_scores(solver)])
  end

  defp format_scores(solver) do
    TopList.to_list(solver.score_list, fn %Attempt{word: word, score: score, expanded?: e?} ->
      str_score = score |> to_string() |> String.slice(0..6) |> String.pad_trailing(6, " ")
      expanded = if(e?, do: "!", else: " ")
      word = String.slice(word, 0..30) |> String.pad_trailing(30)
      [score_emoji(score), "  ", str_score, " ", expanded, " ", word, "\n"]
    end)
  end

  defp score_emoji(score) when score > 0.9999, do: "🥳"
  defp score_emoji(score) when score >= 0.5, do: "😱"
  defp score_emoji(score) when score >= 0.4, do: "🔥"
  defp score_emoji(score) when score >= 0.2, do: "🥵"
  defp score_emoji(score) when score >= 0.1, do: "😎"
  defp score_emoji(score) when score >= 0, do: "🥶"
  defp score_emoji(_), do: "🧊"
end
