import Config

config :cemso,
  cache_dir: Path.expand("_build/cache")

config :logger, :console, format: "$time $metadata[$level] $message\n"
