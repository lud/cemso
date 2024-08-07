defmodule Cemso.DownloaderTest do
  alias Cemso.Downloader
  use ExUnit.Case, async: true

  test "download file prototype" do
    # generate large file
    large_data = :crypto.strong_rand_bytes(10_000_000)
    source_file = Briefly.create!()
    File.write!(source_file, large_data)
    bypass = Bypass.open()
    url = "http://localhost:#{bypass.port}"

    Bypass.expect(bypass, fn conn ->
      IO.puts("called")
      Plug.Conn.send_file(conn, 200, source_file, 0)
    end)

    dest_file = Briefly.create!()

    assert :ok = Downloader.download_file(url, dest_file)

    downloaded = File.read!(dest_file)
    assert downloaded == large_data
  end
end
