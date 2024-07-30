defmodule Cemso.IgnoreFileTest do
  alias Cemso.IgnoreFile
  use ExUnit.Case, async: true

  defp make_path, do: Path.join(Briefly.create!(type: :directory), "some-file.txt")

  test "creates the file when started" do
    path = make_path()
    refute File.regular?(path)
    assert {:ok, pid} = IgnoreFile.start_link(path: path)
    assert File.regular?(path)
    :ok = GenServer.stop(pid)
  end

  test "accepts words to ignore" do
    path = make_path()
    assert {:ok, pid} = IgnoreFile.start_link(path: path)
    assert :ok = IgnoreFile.add(pid, "some_word")
    # file is not written synchronously
    assert "" == File.read!(path)
    # file is written on terminate
    assert :ok = GenServer.stop(pid)
    assert "some_word" == File.read!(path)
  end

  test "loads from file on start and stores as sorted" do
    path = make_path()

    File.write!(path, "ooo\nppp")

    assert {:ok, pid1} = IgnoreFile.start_link(path: path)
    assert :ok = IgnoreFile.add(pid1, "zzz")
    assert :ok = GenServer.stop(pid1)

    assert {:ok, pid2} = IgnoreFile.start_link(path: path)
    assert :ok = IgnoreFile.add(pid2, "aaa")
    assert :ok = GenServer.stop(pid2)

    assert """
           aaa
           ooo
           ppp
           zzz\
           """ == File.read!(path)
  end

  test "can return the ignored words without duplicates" do
    assert {:ok, pid} = IgnoreFile.start_link(path: make_path())
    assert :ok = IgnoreFile.add(pid, "c")
    assert :ok = IgnoreFile.add(pid, "b")
    assert :ok = IgnoreFile.add(pid, "b")
    assert :ok = IgnoreFile.add(pid, "b")
    assert :ok = IgnoreFile.add(pid, "a")
    assert :ok = IgnoreFile.add(pid, "a")
    assert :ok = IgnoreFile.add(pid, "a")

    assert ["a", "b", "c"] = IgnoreFile.to_list(pid)

    :ok = GenServer.stop(pid)
  end
end
