defmodule Cemso.SimEndpoint do
  alias Cemso.WordsTable
  use GenServer
  require Logger

  @gen_opts ~w(name timeout debug spawn_opt hibernate_after)a

  def start_link(opts) do
    {gen_opts, opts} = Keyword.split(opts, @gen_opts)
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  def get_score(word, server) do
    GenServer.call(server, {:get_score, word})
  end

  @impl true
  def init(opts) do
    word = Keyword.fetch!(opts, :word)
    loader = Keyword.fetch!(opts, :loader)
    :ok = WordsTable.subscribe(loader)

    {:ok, %{word: word, loader: loader}, {:continue, :await_loader}}
  end

  @impl true
  def handle_continue(:await_loader, state) do
    %{word: word} = state

    receive do
      {WordsTable, :loaded} ->
        {^word, coords} = WordsTable.get_word(word)
        {:noreply, Map.put(state, :coords, coords)} |> dbg()
    end
  end

  @impl true
  def handle_call({:get_score, candidate_word}, _from, state) do
    %{coords: coords, word: word} = state

    Logger.debug(
      "computing similarity (score) between #{inspect(word)} and #{inspect(candidate_word)}"
    )

    {^candidate_word, candidate_coords} = WordsTable.get_word(candidate_word)
    {:reply, {:ok, WordsTable.similarity(candidate_coords, coords)}, state}
  end
end
