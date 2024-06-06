defmodule Cemso.Utils.BufferTest do
  alias Cemso.Utils.Buffer
  use ExUnit.Case, async: true

  test "can read from a file" do
    file_contents = <<1, 2, 3, 4, 5, 6, 7, 8, 9, 10>>
    path = Briefly.create!()
    File.write!(path, file_contents)
    assert {:ok, buf} = Buffer.open(path)
    assert <<>> == buf.local
  end

  defp buffer_from_bin(binary) do
    file_contents = binary
    path = Briefly.create!()
    File.write!(path, file_contents)
    assert {:ok, buf} = Buffer.open(path)
    buf
  end

  test "ask for more than possible" do
    buf = buffer_from_bin(<<1, 2, 3>>)
    assert %{local: <<1, 2, 3>>} = Buffer.load(buf, 1_000_000)
  end

  test "consume with preload" do
    buf = buffer_from_bin("9999" <> <<1, 2, 3, 4>>)
    assert <<>> = buf.local

    assert {:some_returned, %{local: <<1>>}} =
             Buffer.consume(buf, 5, fn "9999" <> rest ->
               # we return a value and the last byte asked (we matched on 4 but asked 5)
               {:some_returned, rest}
             end)

    assert {:retval, %{local: <<2, 3, 4>>}} =
             Buffer.consume(buf, 10_000, fn untouched ->
               {:retval, untouched}
             end)
  end

  test "close" do
    buf = buffer_from_bin("9999" <> <<1, 2, 3, 4>>)
    assert :ok = Buffer.close(buf)
  end
end
