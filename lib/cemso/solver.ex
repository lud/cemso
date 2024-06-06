defmodule Cemso.Solver do
  alias Cemso.IgnoreFile
  alias Cemso.Utils.TopList
  alias Cemso.WordsTable
  require Logger
  use GenServer

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
    :ok = WordsTable.subscribe(loader)
    {:ok, %{ignore_file: ignore_file}}
  end

  @impl true
  def handle_info({WordsTable, :loaded}, state) do
    Logger.info("Solver starting to solve")
    solve(state)
    {:noreply, state}
  end

  defp solve(state) do
    solver = %{
      test_list: [],
      score_list: TopList.new(40, &compare_score/2),
      closed_list: [],
      ignore_file: state.ignore_file
    }

    loop(solver)
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

        n_rand = 20
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

        loop(%{solver | test_list: new_test_list})

      [%Attempt{word: word, expanded?: false} = top] ->
        n_similar = 20
        Logger.info("Selecting #{n_similar} similar words to #{inspect(word)}")
        new_test_list = similar_words(word, n_similar, solver.closed_list)

        new_score_list =
          solver.score_list |> TopList.drop(top) |> TopList.put(%Attempt{top | expanded?: true})

        loop(%{solver | test_list: new_test_list, score_list: new_score_list})
    end
  end

  defp loop(%{test_list: [h | t]} = solver) do
    # We have items in the test list. We score them one by one
    %{score_list: score_list, closed_list: closed_list} = solver

    # we will not allow this word in the test list again
    solver = %{solver | closed_list: [h | closed_list]}

    case get_score(h) do
      # If we get a score we add that to the score list and remove from the test list
      {:ok, score} ->
        score_list = TopList.put(score_list, %Attempt{word: h, score: score, expanded?: false})
        solver = %{solver | test_list: t, score_list: score_list}

        if score == 1 do
          print_scores(solver)
          Logger.info("Found word for today: #{inspect(h)}", ansi_color: :light_green)
          :ok
        else
          loop(solver)
        end

      # If the word is unknown we only remove from the test list
      {:error, :cemantix_unknown} ->
        Logger.warning("Unknow word #{h}")
        :ok = IgnoreFile.add(solver.ignore_file, h)
        loop(%{solver | test_list: t})
    end
  end

  defp compare_score(%Attempt{score: a}, %Attempt{score: b}) do
    a > b
  end

  defp random_words(n_rand, known_words) do
    (n_rand * 2)
    |> WordsTable.select_random()
    |> Enum.filter(fn word -> word not in known_words end)
    |> Enum.take(n_rand)
  end

  defp similar_words(word, n_similar, known_words) do
    word
    |> WordsTable.select_similar(n_similar * 2)
    |> Enum.filter(fn word -> word not in known_words end)
    |> Enum.take(n_similar)
  end

  defp get_score(word) do
    Logger.info("Requesting score for #{inspect(word)}")
    :ok = Kota.await(Cemantix.RateLimiter)

    Req.post("https://cemantix.certitudes.org/score",
      retry: false,
      body: "word=#{word}",
      headers: %{
        "Content-Type" => "application/x-www-form-urlencoded",
        "Origin" => "https://cemantix.certitudes.org",
        "User-Agent" =>
          "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
      }
    )
    |> case do
      {:ok, %Req.Response{status: 200, body: %{"error" => "Je ne connais pas" <> _}}} ->
        {:error, :cemantix_unknown}

      {:ok, %Req.Response{status: 200, body: "Je ne connais pas" <> _}} ->
        {:error, :cemantix_unknown}

      {:ok, %Req.Response{status: 200, body: %{"score" => score}}} when is_number(score) ->
        {:ok, score}
    end
  end

  defp print_scores(solver) do
    IO.puts(format_scores(solver))
  end

  defp format_scores(solver) do
    TopList.to_list(solver.score_list, fn %Attempt{word: word, score: score, expanded?: e?} ->
      score = score |> to_string() |> String.slice(0..6) |> String.pad_trailing(8)
      expanded = if(e?, do: "! ", else: "  ")
      [score, expanded, word, "\n"]
    end)
  end
end
