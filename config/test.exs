use Mix.Config

config :logger, :console, level: :warn, format: "[$level] $message\n"

config :ex_unit,
  capture_log: true,
  assert_receive_timeout: 1_000

config :commanded,
  dispatch_consistency_timeout: 100,
  event_store_adapter: Commanded.EventStore.Adapters.InMemory
