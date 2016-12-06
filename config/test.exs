use Mix.Config




# dependency injection from config files
config :commanded, Commanded.Storage.Storage,
  adapter: Commanded.Storage.EventStore.Adapter


# Print only warnings and errors during test
config :logger, :console, level: :warn, format: "[$level] $message\n"

config :ex_unit, capture_log: true

config :eventstore, EventStore.Storage,
  serializer: Commanded.Serialization.JsonSerializer,
  username: "postgres",
  password: "postgres",
  database: "commanded_test",
  hostname: "localhost",
  pool_size: 1,
  extensions: [{Postgrex.Extensions.Calendar, []}]
