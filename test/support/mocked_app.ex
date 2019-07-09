defmodule Commanded.MockedApp do
  alias Commanded.EventStore.Adapters.Mock, as: MockEventStore

  use Commanded.Application,
    otp_app: :commanded,
    event_store: [
      adapter: MockEventStore
    ],
    registry: :local,
    pubsub: :local
end
