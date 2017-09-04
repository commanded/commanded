use Mix.Config

# Print only warnings and errors during test
config :logger, :console, level: :debug, format: "[$level] $message\n"

config :ex_unit,
  capture_log: true,
  assert_receive_timeout: 5_000,
  refute_receive_timeout: 2_000

config :eventstore, EventStore.Storage,
  serializer: EventStore.JsonSerializer,
  username: "postgres",
  password: "postgres",
  database: "eventstore_test",
  hostname: "localhost",
  pool_size: 1,
  pool_overflow: 0

config :eventstore,
  registry: :distributed

config :swarm,
  nodes: [:"node1@127.0.0.1", :"node2@127.0.0.1"],
  node_blacklist: [~r/^primary@.+$/],
  sync_nodes_timeout: 0,
  debug: false
