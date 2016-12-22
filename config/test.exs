use Mix.Config

# Print only warnings and errors during test
config :logger, :console, level: :warn, format: "[$level] $message\n"

config :ex_unit,
  capture_log: true,
  assert_receive_timeout: 200

config :eventstore, EventStore.Storage,
  serializer: Commanded.Serialization.JsonSerializer,
  username: "postgres",
  password: "postgres",
  database: "commanded_test",
  hostname: "localhost",
  pool_size: 1,
  extensions: [{Postgrex.Extensions.Calendar, []}]

config :commanded, :extreme,
  db_type: :node, 
  host: "localhost", 
  port: 1113, 
  username: "admin", 
  password: "changeit",
  reconnect_delay: 2_000,
  max_attempts: :infinity

config :commanded,
    event_store_adapter: String.to_atom(
      "Elixir.#{Map.get(System.get_env(), "COMMANDED_EVENT_STORE_ADAPTER", "Commanded.EventStore.Adapters.EventStoreEventStore")}")
