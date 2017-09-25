use Mix.Config

config :logger, :console, level: :warn, format: "[$level] $message\n"

config :ex_unit,
  capture_log: true,
  assert_receive_timeout: 200

config :commanded,
  dispatch_consistency_timeout: 100,
  event_store_adapter: Commanded.EventStore.Adapters.InMemory,
  reset_storage: fn ->
    {:ok, _event_store} = Commanded.EventStore.Adapters.InMemory.start_link()
  end
