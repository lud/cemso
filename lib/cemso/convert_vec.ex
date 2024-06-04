defmodule Cemso.ConvertVec do
  alias Cemso.ConvertVec.Buffer

  def bin2txt(input_path, output_path) do
    with {:ok, buf} <- Buffer.open(input_path) do
      {:ok, do_bin2txt(buf, output_path)}
    end
  end

  defp do_bin2txt(buf, output_path) do
    {n_words, buf} =
      Buffer.consume(buf, 256, fn bin ->
        {n_words, " " <> rest} = Integer.parse(bin)
        {n_words, rest}
      end)

    n_words |> IO.inspect(label: "n_words")

    {n_dimensions, buf} =
      Buffer.consume(buf, 256, fn bin ->
        {n_dimensions, "\n" <> rest} = Integer.parse(bin)
        {n_dimensions, rest}
      end)

    n_dimensions |> IO.inspect(label: "n_dimensions")

    1..n_words
    |> Enum.reduce(buf, fn _, buf ->
      {word, dimensions, buf} = parse_word(buf, n_dimensions)
      word |> IO.inspect(label: "word")
      buf
    end)
  end

  defp parse_word(buf, n_dimensions) do
    {word, buf} =
      Buffer.consume(buf, 50 + n_dimensions * 4, fn bin ->
        [word, rest] = :binary.split(bin, <<32>>)
        {word, rest}
      end)

    {dimensions, buf} =
      Enum.reduce(1..n_dimensions, {[], buf}, fn _, {dimensions, buf} ->
        {dim, buf} =
          Buffer.consume(buf, 4, fn bin ->
            <<x::float-little-size(32), rest::binary>> = bin
            {x, rest}
          end)

        {[dim | dimensions], buf}
      end)

    dimensions = :lists.reverse(dimensions)
    ^n_dimensions = length(dimensions)

    buf = clear_newlines(buf)

    {word, dimensions, buf}
  end

  defp clear_newlines(buf) do
    case Buffer.consume(buf, 1, fn
           <<"\n", rest::binary>> -> {true, rest}
           rest -> {false, rest}
         end) do
      {true, buf} -> clear_newlines(buf)
      {false, buf} -> buf
    end
  end
end
