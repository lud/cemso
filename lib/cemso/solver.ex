defmodule Cemso.Solver do
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
    :ok = WordsTable.subscribe(loader)
    {:ok, %{loader: loader}}
  end

  @impl true
  def handle_info({WordsTable, :loaded}, state) do
    Logger.info("Solver starting to solve")
    solve(state)
  end

  defp solve(_state) do
    init_words = WordsTable.select_random(10)
  end
end
