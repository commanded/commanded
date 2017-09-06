use Mix.Config

config :commanded,
  registry: :local

import_config "#{Mix.env}.exs"
