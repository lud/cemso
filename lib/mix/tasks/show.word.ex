defmodule Mix.Tasks.Show.Word do
  alias Cemso.IgnoreFile
  alias Cemso.CemantixEndpoint
  alias Cemso.Utils.TopList
  alias Cemso.WordsTable
  require Logger
  use Mix.Task

  @shortdoc "Show information about a word"

  @requirements ["app.start"]

  @command [
    name: "mix show.word",
    arguments: [word: [type: :string]]
  ]

  @moduledoc """
  #{@shortdoc}

  #{CliMate.CLI.format_usage(@command, format: :moduledoc)}
  """

  def run(argv) do
    %{word: word} = CliMate.CLI.parse_or_halt!(argv, @command).arguments
    words_table = Cemso.Application.via(:words_table)
    :ok = WordsTable.subscribe(words_table)

    receive do
      {WordsTable, :loaded} -> :ok
    end

    number_of_words_to_show = 10
    number_of_words_to_select = number_of_words_to_show * 10

    similar_out =
      word
      |> WordsTable.select_similar(number_of_words_to_select, [word])
      |> toplist_to_cemantix_existing_display(number_of_words_to_show)

    dissimilar_out =
      word
      |> WordsTable.select_dissimilar(number_of_words_to_select, [word])
      |> toplist_to_cemantix_existing_display(number_of_words_to_show)

    IO.puts("""

    == Similar to #{word}

    #{similar_out}

    == Dissimilar to #{word}

    #{dissimilar_out}
    """)

    System.stop()
  end

  defp toplist_to_cemantix_existing_display(toplist, amount) do
    toplist
    |> TopList.to_list()
    |> Stream.filter(fn {_, w} -> cemantix_exists?(w) end)
    |> Stream.take(amount)
    |> Enum.map(fn {score, word} ->
      [format_score(score), "  ", word, "\n"]
    end)
  end

  defp cemantix_exists?(word) do
    case CemantixEndpoint.get_score(word, "Checking if exists in Cémantix: #{inspect(word)}") do
      {:ok, _} ->
        true

      {:error, :cemantix_unknown} ->
        Logger.warning("Unknown word #{inspect(word)}")
        :ok = IgnoreFile.add(Cemso.Application.via(:ignore_file), word)
        false

      other ->
        Logger.error("cemantix error: " <> inspect(other))
        false
    end
  end

  defp format_score(score) do
    score |> to_string() |> String.slice(0..5) |> String.pad_trailing(5, "0")
  end
end
