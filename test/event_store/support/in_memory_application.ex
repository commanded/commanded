defmodule InMemoryApplication do
  use Commanded.Application,
    otp_app: :commanded,
    event_store: [
      adapter: Commanded.EventStore.Adapters.InMemory,
      serializer: Commanded.Serialization.JsonSerializer
    ]
end
