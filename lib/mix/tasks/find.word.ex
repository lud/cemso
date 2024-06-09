defmodule Mix.Tasks.Find.Word do
  use Mix.Task

  @moduledoc """
  Runs a deoptimized algorithm to find the current Cémantix solution.
  """
  alias Cemso.CemantixEndpoint
  alias Cemso.SimEndpoint
  @shortdoc "Finds the Cémantix word"

  @requirements ["app.start"]

  @command [
    options: [
      simulate: [
        type: :string
      ]
    ]
  ]

  def run(argv) do
    %{options: options} = CliMate.CLI.parse_or_halt!(argv, @command)

    solver_opts = [
      loader: Cemso.Application.via(:loader),
      ignore_file: Cemso.Application.via(:ignore_file)
    ]

    solver_opts =
      case options do
        %{simulate: word} ->
          {:ok, simulator} =
            Supervisor.start_child(
              Cemso.Supervisor,
              {SimEndpoint, word: word, loader: Cemso.Application.via(:loader)}
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
  end
end