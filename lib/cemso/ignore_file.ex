defmodule Cemso.IgnoreFile do
  require Logger
  use GenServer

  @gen_opts ~w(name timeout debug spawn_opt hibernate_after)a

  def start_link(opts) do
    {gen_opts, opts} = Keyword.split(opts, @gen_opts)
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  def add(server, word) when is_binary(word) do
    GenServer.call(server, {:add, word})
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

    {:ok, %{words: words, path: path, write_after: write_after}}
  end

  @impl true
  def handle_call({:add, word}, from, state) do
    GenServer.reply(from, :ok)
    state = %{state | words: insert(state.words, word)}
    {:noreply, state, state.write_after}
  end

  @impl true
  def handle_call(:to_list, _from, state) do
    {:reply, state.words, state, state.write_after}
  end

  @impl true
  def handle_info(:timeout, state) do
    :ok = write_file(state)
    {:noreply, state, :infinity}
  end

  @impl true
  def terminate(_reason, state) do
    write_file(state)
  end

  defp write_file(state) do
    state.words
    |> Enum.map(&(&1 <> "\n"))
    |> Enum.into(File.stream!(state.path))
    |> then(fn _ -> Logger.debug("wrote ignore file") end)

    :ok
  end

  defp insert([h | t], word) when word < h, do: [word, h | t]
  defp insert([h | t], word) when word > h, do: [h | insert(t, word)]
  defp insert([], word), do: [word]
  defp insert([word | t], word), do: t
end
