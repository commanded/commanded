use Mix.Config


config :commanded, Repo,
  adapter: Commanded.Adapters.Postgres


config :eventstore, EventStore.Storage,
  serializer: Commanded.Serialization.JsonSerializer,
  username: "postgres",
  password: "postgres",
  database: "commanded_dev",
  hostname: "localhost",
  pool_size: 10,
  extensions: [{Postgrex.Extensions.Calendar, []}]
