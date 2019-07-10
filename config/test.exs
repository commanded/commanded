use Mix.Config

alias Commanded.EventStore.Adapters.InMemory
alias Commanded.Serialization.JsonSerializer

config :logger, :console, level: :warn, format: "[$level] $message\n"

config :ex_unit,
  capture_log: true,
  assert_receive_timeout: 1_000

config :commanded,
  assert_receive_event_timeout: 100,
  refute_receive_event_timeout: 100,
  dispatch_consistency_timeout: 100,
  event_store_adapter: InMemory

config :commanded, InMemory, serializer: JsonSerializer

config :commanded, Commanded.TestApplication,
  event_store: [adapter: InMemory, serializer: JsonSerializer],
  pubsub: :local,
  registry: :local

config :commanded, Commanded.DefaultApp,
  event_store: [adapter: InMemory, serializer: JsonSerializer],
  pubsub: :local,
  registry: :local
