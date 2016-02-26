use Mix.Config

# no logging for benchmarking
config :logger, backends: []

config :eventstore, EventStore.Storage,
  username: "postgres",
  password: "postgres",
  database: "eventstore_bench",
  hostname: "localhost"
