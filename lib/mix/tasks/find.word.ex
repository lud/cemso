defmodule Mix.Tasks.Find.Word do
  alias Cemso.CemantixEndpoint
  alias Cemso.SimEndpoint
  use Mix.Task

  @shortdoc "Finds the Cémantix word"

  @requirements ["app.start"]

  @command [
    name: "mix find.word",
    options: [
      init: [
        type: :string,
        doc: """
        A list of words to start with, separated by commas and/or spaces.
        """,
        doc_arg: "word1,word2"
      ],
      simulate: [
        type: :string,
        doc: """
        Do not send requests to cemantix.certitudes.org.

        Use the provided word as the correct answer.
        """,
        doc_arg: "word"
      ],
      fast: [
        type: :boolean,
        default: false,
        doc: "Uses a fast but cheating algorithm."
      ]
    ]
  ]

  @moduledoc """
  Runs a deoptimized algorithm to find the current Cémantix solution.

  #{CliMate.CLI.format_usage(@command, format: :moduledoc)}
  """

  def run(argv) do
    %{options: options} = CliMate.CLI.parse_or_halt!(argv, @command)

    solver_opts = [
      words_table: Cemso.Application.via(:words_table),
      ignore_file: Cemso.Application.via(:ignore_file),
      init_list: parse_test_list(options[:init]),
      fast: options.fast
    ]

    solver_opts =
      case options do
        %{simulate: word} ->
          {:ok, simulator} =
            Supervisor.start_child(
              Cemso.Supervisor,
              {SimEndpoint, word: word, words_table: Cemso.Application.via(:words_table)}
            )

          [{:score_adapter, {SimEndpoint, [simulator]}} | solver_opts]

        _ ->
          [{:score_adapter, {CemantixEndpoint, []}} | solver_opts]
      end

    {:ok, solver} = Supervisor.start_child(Cemso.Supervisor, {Cemso.Solver, solver_opts})

    ref = Process.monitor(solver)

    receive do
      {:DOWN, ^ref, :process, ^solver, _} -> :ok
    end

    System.stop()
  end

  defp parse_test_list(words) when is_binary(words) do
    String.split(words, ~r/[, ]/, trim: true)
  end

  defp parse_test_list(nil) do
    []
  end
end
