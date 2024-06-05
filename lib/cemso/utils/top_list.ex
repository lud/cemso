defmodule Cemso.Utils.TopList do
  # Comparator function must return true if the first argument should be
  # before the second argument in the top.

  def new(max_items, comp)
      when is_integer(max_items) and max_items > 0 and is_function(comp, 2) do
    {max_items, comp, []}
  end

  def to_list({_, _, list}) do
    list
  end

  def to_list({_, _, list}, mapper) do
    Enum.map(list, mapper)
  end

  def put({max_items, comp, list}, item) do
    {max_items, comp, insert(list, item, max_items, comp)}
  end

  defp insert(_, _, 0, _) do
    []
  end

  defp insert([h | t], item, max_items, comp) do
    case comp.(item, h) do
      true -> [item | delete([h | t], max_items - 1)]
      false -> [h | insert(t, item, max_items - 1, comp)]
    end
  end

  defp insert([], item, _max_items, _comp) do
    [item]
  end

  defp delete(_, 0) do
    []
  end

  defp delete([h | t], max_items) do
    [h | delete(t, max_items - 1)]
  end

  defp delete([], _) do
    []
  end

  def empty?({_, _, []}), do: true
  def empty?(_), do: false

  def drop({max_items, comp, list}, item) do
    {max_items, comp, list -- [item]}
  end
end
