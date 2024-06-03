defmodule WttjEtl.Utils.TransformCollectable do
  defstruct [:target, :mapper]

  def transform(target, mapper) do
    %__MODULE__{target: target, mapper: mapper}
  end

  defimpl Collectable do
    def into(%{target: target, mapper: mapper}) do
      {acc, subfun} = Collectable.into(target)

      fun = fn
        acc, {:cont, elem} -> subfun.(acc, {:cont, mapper.(elem)})
        acc, ctrl -> subfun.(acc, ctrl)
      end

      {acc, fun}
    end
  end
end
