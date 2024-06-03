defmodule CemsoTest do
  use ExUnit.Case
  doctest Cemso

  test "greets the world" do
    assert Cemso.hello() == :world
  end
end
