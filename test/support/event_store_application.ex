defmodule EventStoreApplication do
  use Commanded.Application,
    otp_app: :commanded,
    event_store: [
      adapter: Commanded.EventStore.Adapters.EventStore,
      event_store: TestEventStore
    ]
end
