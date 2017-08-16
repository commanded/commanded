use Mix.Config

config :eventstore,
  registry: :local

import_config "#{Mix.env}.exs"
