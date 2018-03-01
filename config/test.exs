use Mix.Config

alias Commanded.EventStore.Adapters.InMemory
alias Commanded.Serialization.JsonSerializer

config :logger, :console, level: :warn, format: "[$level] $message\n"

config :ex_unit,
  capture_log: true,
  assert_receive_timeout: 200

config :commanded,
  dispatch_consistency_timeout: 100,
  event_store_adapter: InMemory,
  reset_storage: fn ->
    with {:ok, _pid} <- InMemory.start_link(serializer: JsonSerializer) do
      :ok
    end
  end
