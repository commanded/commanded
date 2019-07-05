defmodule Commanded.ExampleApplication do
  alias Commanded.EventStore.Adapters.InMemory
  alias Commanded.Serialization.JsonSerializer

  use Commanded.Application,
    otp_app: :commanded,
    event_store: [
      adapter: InMemory,
      serializer: JsonSerializer
    ]
end
