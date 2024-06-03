import Config

config :cemso,
  cache_dir: Path.expand("_build/cache")

config :logger, :console, format: "$metadata[$level] $message\n"
