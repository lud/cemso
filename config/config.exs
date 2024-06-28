import Config

config :cemso,
  cache_dir: Path.expand("_build/cache"),
  source: :frWac_non_lem_no_postag_no_phrase_200_skip_cut100,
  # source: :frWac_non_lem_no_postag_no_phrase_500_skip_cut200,
  # source: :frWac_non_lem_no_postag_no_phrase_200_cbow_cut100,
  ignore_file: Path.join([File.cwd!(), "priv", "ignored"])

config :logger, :console, format: "$metadata[$level] $message\n"
