defmodule Cemso.ConvertVec do
  def bin2txt(input_path, output_path) do
  end
end


Cemso.SourceData.download_source(:frWac_non_lem_no_postag_no_phrase_200_skip_cut100)
# input_path = Cemso.SourceData.download_path(:frWac_non_lem_no_postag_no_phrase_200_skip_cut100)

# dest_path = Briefly.create!()

# dest_path |> IO.inspect(label: "dest_path")
# Cemso.ConvertVec.bin2txt(input_path, dest_path)
# "%lld"

defmodule S do
  def parse_fstream!(path, size, init_state, fun) do
    stream =
      File.stream!(path, 4096)
      |> Stream.each(&IO.inspect/1)
      |> Enum.reduce(initial(init_state, fun), &reducer/2)
  end

  def initial(init_state, fun) do
    %{buffer: <<>>, substate: init_state, fun: fun}
  end

  defp reducer(chunk, state) do
    reducer(append_buffer(chunk, state))
  end

  defp append_buffer(chunk, %{buffer: buffer} = state) do
    %{state | buffer: <<buffer::binary, chunk::binary>>} |> dbg()
  end

  defp reducer(state) do
    %{substate: substate, fun: fun, buffer: buffer} = state

    case state.fun.(state.buffer, state.substate) do
      {:next, leftover, bytes_to_have, substate} ->
        state = %{state | substate: substate, buffer: leftover}

        if bytes_to_have < byte_size(leftover) do
          state
        else
          reducer(state)
        end
    end
  end
end

sizeof_c_float = 32

defmodule P do
  def progress(state) do
    IO.puts("processed #{state.processed}, remaining #{state.remaining}")
  end
end

S.parse_fstream!(
  "/home/lud/src/cemso/_build/cache/frWac_non_lem_no_postag_no_phrase_200_skip_cut100.bin",
  4096,
  :initial,
  fn
    buf, %{stage: :new_word} = state ->
      [word, buf] = :binary.split(buf, <<32>>)

      word |> dbg()
      buf |> dbg()

      state =
        Map.merge(state, %{
          stage: :process_word,
          word: word,
          rem_dimensions: state.dimensions,
          floats: []
        })

      {:next, buf, state.dimensions * sizeof_c_float, state}

    buf, %{stage: :process_word, rem_dimensions: remd, floats: floats} when remd > 0 ->
      <<x::float-little-size(32), buf::binary>> = buf
      x |> IO.inspect(label: "x")
      raise "ok"

    buf, :initial ->
      {wordcount, " " <> buf} = Integer.parse(buf)
      {dimensions, "\n" <> buf} = Integer.parse(buf)
      wordcount |> IO.inspect(label: "wordcount")
      dimensions |> IO.inspect(label: "dimensions")
      state = %{dimensions: dimensions, remaining: wordcount, processed: 0, stage: :new_word}
      P.progress(state)
      {:next, buf, dimensions * sizeof_c_float + 2000, state}
  end
)
