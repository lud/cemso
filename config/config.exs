import Config

config :cemso,
  cache_dir: Path.expand("_build/cache"),
  source: :frWac_non_lem_no_postag_no_phrase_200_skip_cut100

config :logger, :console, format: "$metadata[$level] $message\n"
