use Mix.Config

# Print only warnings and errors during test
config :logger, :console, level: :debug, format: "[$level] $message\n"

config :ex_unit,
  capture_log: true,
  assert_receive_timeout: 2_000

config :eventstore, EventStore.Storage,
  serializer: EventStore.JsonSerializer,
  username: "postgres",
  password: "postgres",
  database: "eventstore_test",
  hostname: "localhost",
  pool_size: 1,
  pool_overflow: 0
