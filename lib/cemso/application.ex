defmodule Cemso.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    source = Application.fetch_env!(:cemso, :source)

    children = [
      {Registry, keys: :unique, name: Cemso.Reg},
      {Cemso.WordsTable, source: source, name: {:via, Registry, {Cemso.Reg, :loader}}},
      {Cemso.Solver, loader: {:via, Registry, {Cemso.Reg, :loader}}}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Cemso.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
