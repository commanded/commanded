defmodule Commanded.Registration.HandleFunctionDelegationApp do
  alias Commanded.EventStore.Adapters.InMemory
  alias Commanded.Registration.HandleFunctionDelegationRegistry
  alias Commanded.Serialization.JsonSerializer

  use Commanded.Application,
    otp_app: :commanded,
    event_store: [
      adapter: InMemory,
      serializer: JsonSerializer
    ],
    pubsub: :local,
    registry: HandleFunctionDelegationRegistry
end
