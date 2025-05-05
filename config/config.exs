import Config

# source= :frWac_non_lem_no_postag_no_phrase_200_skip_cut100
# source= :frWac_non_lem_no_postag_no_phrase_500_skip_cut200
source = :frWac_non_lem_no_postag_no_phrase_200_cbow_cut100
# source= :frWac_no_postag_no_phrase_500_cbow_cut100

config :cemso,
  cache_dir: Path.expand("_build/cache"),
  source: source,
  ignore_file: Path.join([File.cwd!(), "priv", "ignored-#{source}"])

config :logger, :console, format: "$metadata[$level] $message\n"

config :elixir, :time_zone_database, Tz.TimeZoneDatabase
