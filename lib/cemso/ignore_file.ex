defmodule Cemso.IgnoreFile do
  require Logger
  use GenServer

  @gen_opts ~w(name timeout debug spawn_opt hibernate_after)a

  def start_link(opts) do
    {gen_opts, opts} = Keyword.split(opts, @gen_opts)
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  def add(server, word) when is_binary(word) do
    GenServer.cast(server, {:add, word})
  end

  def to_list(server) do
    GenServer.call(server, :to_list)
  end

  def force_write(server) do
    GenServer.call(server, :force_write)
  end

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    path = Keyword.fetch!(opts, :path)
    write_after = Keyword.get(opts, :write_after, 1000)

    words =
      case File.read(path) do
        {:error, :enoent} ->
          Logger.info("Creating ignore file #{path}")
          :ok = File.touch!(path)
          []

        {:ok, contents} ->
          String.split(contents, "\n", trim: true)
      end

    {:ok, %{words: words, path: path, write_after: write_after, tainted: false}}
  end

  @impl true
  def handle_cast({:add, word}, state) do
    state = %{state | words: [word | state.words], tainted: true}
    {:noreply, state, state.write_after}
  end

  @impl true
  def handle_call(:to_list, _from, state) do
    {:reply, state.words, state, state.write_after}
  end

  @impl true
  def handle_call(:force_write, _from, state) do
    {:ok, state} = write_file(state)
    {:reply, :ok, %{state | tainted: false}, state.write_after}
  end

  @impl true
  def handle_info(:timeout, state) do
    state =
      if state.tainted do
        {:ok, state} = write_file(state)
        state
      else
        state
      end

    {:noreply, state, :infinity}
  end

  @impl true
  def terminate(_reason, state) do
    Logger.debug("Ignore file terminating with write")
    write_file(state)
  end

  defp write_file(state) do
    words =
      state.words
      |> Enum.uniq()
      |> Enum.sort()

    :ok =
      words
      |> Stream.intersperse("\n")
      |> Enum.into(File.stream!(state.path))
      |> then(fn _ -> Logger.debug("wrote ignore file") end)

    {:ok, %{state | tainted: false, words: words}}
  end
end
