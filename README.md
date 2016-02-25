# EventStore

CQRS Event Store implemented in Elixir.

Uses [PostgreSQL](http://www.postgresql.org/) as the underlying storage. Requires version 9.5 or newer.

## Sample usage

```elixir
# start the Storage process
{:ok, store} = EventStore.Storage.start_link

# ensure PostgreSQL tables exist (create if not present) 
EventStore.Storage.initialize_store!(store)
```

### Writing to a Stream

```elixir
# create a unique identity for the stream
stream_uuid = UUID.uuid4()

# list of events to persist
events = [
  %EventStore.EventData{
  	headers: %{user: "someuser@example.com"},
    payload: %ExampleEvent{key: "value"}
  }
]

# append events to a stream (as expected version is 0, a new stream will be created)
{:ok, events} = EventStore.append_to_stream(store, stream_uuid, 0, events)
```

### Reading Events

```elixir
# read all events from the stream, starting at the beginning (as from version is 0)
{:ok, recorded_events} = EventStore.read_stream_forward(store, uuid, 0)
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

