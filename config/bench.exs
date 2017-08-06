use Mix.Config

# no logging for benchmarking
config :logger, backends: []

config :eventstore, EventStore.Storage,
  serializer: EventStore.TermSerializer,
  username: "postgres",
  password: "postgres",
  database: "eventstore_bench",
  hostname: "localhost",
  pool: DBConnection.Poolboy,
  pool_size: 10
