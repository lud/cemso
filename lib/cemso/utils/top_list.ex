defmodule Cemso.Utils.TopList do
  # Comparator function must return true if the first argument should be
  # before the second argument in the top.

  defstruct max: 0, comp: nil, items: []

  def new(max_items, comp)
      when is_integer(max_items) and max_items > 0 and is_function(comp, 2) do
    %__MODULE__{max: max_items, comp: comp, items: []}
  end

  def to_list(%__MODULE__{items: items}) do
    items
  end

  def to_list(%__MODULE__{items: items}, mapper) do
    Enum.map(items, mapper)
  end

  def put(toplist, item) do
    %__MODULE__{items: items, comp: comp, max: max} = toplist
    %__MODULE__{toplist | items: insert(items, item, max, comp)}
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

  def empty?(%{items: []}), do: true
  def empty?(_), do: false

  def drop(%__MODULE__{items: items} = toplist, item) do
    %__MODULE__{toplist | items: items -- [item]}
  end

  def map(%__MODULE__{items: items} = toplist, f) do
    %__MODULE__{toplist | items: Enum.map(items, f)}
  end

  def filter(%__MODULE__{items: items} = toplist, f) do
    %__MODULE__{toplist | items: Enum.filter(items, f)}
  end
end

defimpl Enumerable, for: Cemso.Utils.TopList do
  alias Cemso.Utils.TopList
  def reduce(%{items: items}, arg, fun), do: Enumerable.List.reduce(items, arg, fun)
  def count(%{items: items}), do: {:ok, length(items)}
  def member?(%{items: items}, item), do: {:ok, item in items}
  def slice(%{items: items}), do: {:ok, length(items), &TopList.to_list/1}
end
