use Mix.Config

config :eventstore, EventStore.Storage,
  serializer: Commanded.Event.JsonSerializer,
  username: "postgres",
  password: "postgres",
  database: "eventstore_dev",
  hostname: "localhost",
  pool_size: 10
