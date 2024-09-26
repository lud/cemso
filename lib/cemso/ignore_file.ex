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
  def handle_info(:timeout, state) do
    if state.tainted do
      :ok = write_file(state)
    end

    {:noreply, %{state | tainted: false}, :infinity}
  end

  @impl true
  def terminate(_reason, state) do
    Logger.debug("Ignore file terminating with write")
    write_file(state, true)
  end

  defp write_file(state, clean? \\ false) do
    words =
      if clean?,
        do: state.words |> Enum.uniq() |> Enum.sort(),
        else: state.words

    words
    |> Stream.intersperse("\n")
    |> Enum.into(File.stream!(state.path))
    |> then(fn _ -> Logger.debug("wrote ignore file") end)

    :ok
  end
end
