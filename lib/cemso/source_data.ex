defmodule Cemso.SourceData do
  alias Cemso.Downloader
  require Logger

  @sources %{
    frWac_non_lem_no_postag_no_phrase_200_skip_cut100: %{
      url:
        "https://embeddings.net/embeddings/frWac_non_lem_no_postag_no_phrase_200_skip_cut100.bin",
      md5: "6b8605bb1fc726f44a895bff26057bae"
    },
    frWac_non_lem_no_postag_no_phrase_500_skip_cut200: %{
      url:
        "https://embeddings.net/embeddings/frWac_non_lem_no_postag_no_phrase_500_skip_cut200.bin",
      md5: "e2c626ef894a6d2ef2524880e1856558"
    },
    frWac_non_lem_no_postag_no_phrase_200_cbow_cut100: %{
      url:
        "https://embeddings.net/embeddings/frWac_non_lem_no_postag_no_phrase_200_cbow_cut100.bin",
      md5: "5b5ffb3320999ae5536ac4a0f101faf3"
    },
    frWac_no_postag_no_phrase_500_cbow_cut100: %{
      url: "https://embeddings.net/embeddings/frWac_no_postag_no_phrase_500_cbow_cut100.bin",
      md5: "1c852a388a9bd610f84de6bdee87d8a9"
    }
  }

  defp cache_dir, do: Application.fetch_env!(:cemso, :cache_dir)

  def download_path(key) do
    Path.join(cache_dir(), "#{key}.bin")
  end

  def download_source(key) do
    %{url: url, md5: md5} = Map.fetch!(@sources, key)
    cache_dir = cache_dir()
    File.mkdir_p!(cache_dir)
    temp_path = Path.join(cache_dir, "#{key}.dl")
    dest_path = Path.join(cache_dir, "#{key}.bin")
    Logger.info("Downloading source #{key}")

    with :error <- check_existing(dest_path, md5),
         :ok <- Downloader.download_file(url, temp_path),
         :ok <- check_sum(temp_path, md5),
         :ok <- rename_file(temp_path, dest_path) do
      Logger.info("File download complete", ansi_color: :green)
      :ok = check_sum(dest_path, md5)
    else
      {:ok, :already_in_cache} -> :ok
      {:error, _} = err -> err
    end
  end

  defp check_existing(dest_path, expected_md5) do
    with true <- File.regular?(dest_path),
         _ = Logger.info("Found existing file: #{dest_path}"),
         :ok <- check_sum(dest_path, expected_md5) do
      Logger.info("Validated cache")
      {:ok, :already_in_cache}
    else
      _ -> :error
    end
  end

  defp check_sum(path, expected) do
    Logger.debug("Expected md5 sum: #{expected}")
    hash = :crypto.hash_init(:md5)

    actual =
      path
      |> File.stream!(2048, [])
      |> Enum.reduce(hash, fn bytes, hash_state ->
        :crypto.hash_update(hash_state, bytes)
      end)
      |> :crypto.hash_final()
      |> Base.encode16(case: :lower)

    Logger.debug("Actual   md5 sum: #{actual}")

    if actual == expected do
      :ok
    else
      Logger.error("Checksum error")

      {:error, :checksum_error}
    end
  end

  defp rename_file(from, to) do
    Logger.debug("Renaming file #{from} to #{to}")
    File.rename(from, to)
  end
end
