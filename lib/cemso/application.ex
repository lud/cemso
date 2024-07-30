defmodule Cemso.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    %{
      # TODO pass cache dir
      # cache_dir: cache_dir,
      source: source,
      ignore_file: ignore_file
    } = Application.get_all_env(:cemso) |> Map.new()

    children = [
      {Registry, keys: :unique, name: Cemso.Reg},
      {Kota,
       name: Cemantix.RateLimiter,
       max_allow: 1,
       range_ms: 50,
       adapter: Kota.Bucket.DiscreteCounter},
      {Cemso.IgnoreFile, name: via(:ignore_file), path: ignore_file, write_after: 250},
      {Cemso.WordsTable, source: source, name: via(:loader), ignore_file: via(:ignore_file)}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Cemso.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def via(key), do: {:via, Registry, {Cemso.Reg, key}}
end
