# EventStore

CQRS Event Store implemented in Elixir.

Uses [PostgreSQL](http://www.postgresql.org/) as the underlying storage. Requires version 9.5 or newer.

## Sample usage

```elixir
# start the `EventStore` process
{:ok, store} = EventStore.Storage.start_link

# ensure PostgreSQL tables exist (create if not present) 
EventStore.Storage.initialize_store!(store)

# create a unique identity for the stream (e.g. an aggregate id)
uuid = UUID.uuid4()

# list of events to persist
events = [
  %EventStore.EventData{
  	event_type: "ExampleEvent",
    headers: %{user: "someuser@example.com"},
    payload: %ExampleEvent{key: "value"}
  }
]

# append events to the stream
{:ok, events} = EventStore.Storage.append_to_stream(store, uuid, 0, events)
```

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed as:

  1. Add eventstore to your list of dependencies in `mix.exs`:

        def deps do
          [{:eventstore, "~> 0.0.1"}]
        end

  2. Ensure eventstore is started before your application:

        def application do
          [applications: [:eventstore]]
        end

