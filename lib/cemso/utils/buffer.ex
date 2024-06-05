defmodule Cemso.Utils.Buffer do
  defstruct handle: nil, local: <<>>

  def open(path) do
    with {:ok, handle} <- File.open(path, [:read, :binary]) do
      {:ok, %__MODULE__{handle: handle, local: <<>>}}
    end
  end

  def load(%{handle: handle, local: local} = buf, n_bytes) do
    local_size = byte_size(local)

    case max(0, n_bytes - local_size) do
      0 ->
        buf

      n ->
        case IO.binread(handle, n) do
          :eof -> buf
          data -> %{buf | local: <<local::binary, data::binary>>}
        end
    end
  end

  def consume(buf, preload, consumer) do
    buf = load(buf, preload)
    {return_val, remaining_local} = consumer.(buf.local)
    {return_val, %{buf | local: remaining_local}}
  end

  def close(%{handle: handle}) do
    File.close(handle)
  end
end
