use Mix.Config



# dependency injection from config files
config :commanded, Commanded.Storage.Storage,
  adapter: Commanded.Storage.EventStore.Adapter



config :eventstore, EventStore.Storage,
  serializer: Commanded.Serialization.JsonSerializer,
  username: "postgres",
  password: "postgres",
  database: "commanded_dev",
  hostname: "localhost",
  pool_size: 10,
  extensions: [{Postgrex.Extensions.Calendar, []}]
