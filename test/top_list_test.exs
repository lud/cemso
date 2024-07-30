defmodule Cemso.Utils.TopListTest do
  alias Cemso.Utils.TopList
  use ExUnit.Case, async: true

  test "can be initialized as empty" do
    toplist = TopList.new(10, fn _, _ -> nil end)
    assert [] = TopList.to_list(toplist)
  end

  test "items are inserted and ordered in the list" do
    # Use "is greater than" as comparator, sor higher items will be first
    toplist =
      TopList.new(10, &Kernel.>/2)
      |> TopList.put(1)
      |> TopList.put(2)
      |> TopList.put(1)
      |> TopList.put(4)
      |> TopList.put(2)

    assert [4, 2, 2, 1, 1] = TopList.to_list(toplist)
  end

  test "list deletes old entries when new item is prepended" do
    # Use increasing items to force delete at the tail

    toplist = TopList.new(5, &Kernel.>/2)
    toplist = Enum.reduce(1..10, toplist, fn item, toplist -> TopList.put(toplist, item) end)
    assert [10, 9, 8, 7, 6] = TopList.to_list(toplist)
  end

  test "list discards new entries on overflow" do
    # Use decreasing items to push unwanted entries beyond the tail

    toplist = TopList.new(5, &Kernel.>/2)
    toplist = Enum.reduce(10..1, toplist, fn item, toplist -> TopList.put(toplist, item) end)
    assert [10, 9, 8, 7, 6] = TopList.to_list(toplist)
  end

  test "to list with mapper" do
    toplist = TopList.new(3, &Kernel.>/2)
    toplist = Enum.reduce(1..10, toplist, fn item, toplist -> TopList.put(toplist, item) end)

    assert [100, 90, 80] = TopList.to_list(toplist, &(&1 * 10))
  end

  test "empty?" do
    assert TopList.empty?(TopList.new(10, &Kernel.>/2))
    refute TopList.empty?(TopList.new(10, &Kernel.>/2) |> TopList.put(123))
  end

  test "drop" do
    toplist = TopList.new(5, &Kernel.>/2)
    toplist = Enum.reduce(10..1, toplist, fn item, toplist -> TopList.put(toplist, item) end)
    assert [10, 8, 7, 6] = TopList.drop(toplist, 9) |> TopList.to_list()
  end

  test "map" do
    empty = TopList.new(3, &Kernel.>/2)
    toplist = Enum.reduce(10..1, empty, fn item, toplist -> TopList.put(toplist, item) end)
    mapped = TopList.map(toplist, fn x -> x * 10 end)
    assert [100, 90, 80] = TopList.to_list(mapped)
  end

  test "map does not change ordering" do
    empty = TopList.new(3, &Kernel.>/2)
    toplist = Enum.reduce(10..1, empty, fn item, toplist -> TopList.put(toplist, item) end)
    mapped = TopList.map(toplist, fn x -> x * -1 end)
    assert [-10, -9, -8] = TopList.to_list(mapped)
  end

  describe "Enumerable" do
    test "reduce" do
      toplist = TopList.new(5, &Kernel.>/2)

      toplist =
        Enum.reduce(10..1, toplist, fn item, toplist -> TopList.put(toplist, item) end)

      assert [10, 9, 8, 7, 6] = Enum.take(toplist, 5)
      assert [10, 9, 8, 7, 6] = Enum.take(toplist, 1_000_000)
      assert [10, 9, 8] = Enum.take(toplist, 3)
      assert [10, 9, 8] = Enum.take(toplist, 3)
      assert [7, 6] = Enum.drop(toplist, 3)
    end

    test "count" do
      empty = TopList.new(5, &Kernel.>/2)

      toplist =
        Enum.reduce(10..1, empty, fn item, toplist -> TopList.put(toplist, item) end)

      assert 5 == Enum.count(toplist)

      toplist =
        Enum.reduce(1..2, empty, fn item, toplist -> TopList.put(toplist, item) end)

      assert 2 == Enum.count(toplist)
    end

    test "member?" do
      toplist = TopList.new(5, &Kernel.>/2)

      toplist =
        Enum.reduce(10..1, toplist, fn item, toplist -> TopList.put(toplist, item) end)

      assert Enum.member?(toplist, 10)
      refute Enum.member?(toplist, 100)
    end

    test "slice" do
      empty = TopList.new(5, &Kernel.>/2)

      toplist =
        Enum.reduce(10..1, empty, fn item, toplist -> TopList.put(toplist, item) end)

      assert [10, 9, 8] = Enum.slice(toplist, 0..2)

      assert [10, 9, 8, 7, 6] = Enum.slice(toplist, 0..200_000)
    end
  end
end
