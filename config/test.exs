use Mix.Config

# Print only warnings and errors during test
config :logger, :console, level: :warn, format: "[$level] $message\n"

config :eventstore, EventStore.Storage,
  username: "postgres",
  password: "postgres",
  database: "eventstore_test",
  hostname: "localhost"
