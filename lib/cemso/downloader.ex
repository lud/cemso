defmodule Cemso.Downloader do
  require Logger
  # alias WttjEtl.Utils.TransformCollectable

  def download_file(url, dest_path) do
    # output = TransformCollectable.transform(File.stream!(dest_path), &log_download/1)
    output = File.stream!(dest_path)
    Logger.info("Downloading #{url} to #{dest_path}")

    case Req.get(url: url, into: output) do
      {:ok, %{status: status}} when status in 200..299 ->
        Logger.info("Download complete with status #{status} at #{dest_path}")
        :ok

      {:ok, %{status: status} = reason} ->
        Logger.error("Download failed with status #{status}")
        {:error, reason}

      {:error, reason} = err ->
        Logger.error("Download failed with reason #{inspect(reason)}")
        {:error, reason}
        err
    end
  end

  defp log_download(binary) do
    Logger.debug("Downloaded #{byte_size(binary)}b")
    binary
  end
end
