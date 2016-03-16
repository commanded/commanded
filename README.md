# EventStore

CQRS Event Store implemented in Elixir. Uses [PostgreSQL](http://www.postgresql.org/) as the underlying storage. Requires version 9.5 or newer.

License is MIT.

## Getting started

EventStore is [available in Hex](https://hex.pm/packages/eventstore), the package can be installed as follows:

  1. Add eventstore to your list of dependencies in `mix.exs`:

        def deps do
          [{:eventstore, "~> 0.0.1"}]
        end

  2. Ensure eventstore is started before your application:

        def application do
          [applications: [:eventstore]]
        end

  3. Add an `eventstore` config entry containing the PostgreSQL connection details to each environment's mix config file (e.g. `config/dev.exs`).

    ```elixir
    config :eventstore, EventStore.Storage,
      username: "postgres",
      password: "postgres",
      database: "eventstore_dev",
      hostname: "localhost"
    ```

  4. Create the EventStore database using the `mix` task

    ```
    mix event_store.create
    ```

    This will create the database and tables.

## Sample usage

```elixir
# ensure EventStore application is started
Application.ensure_all_started(:eventstore)
```

### Writing to a stream

```elixir
# create a unique identity for the stream
stream_uuid = UUID.uuid4()

# a new stream will be created when the expected version is zero
expected_version = 0

# list of events to persist
# - headers and payload must already be serialized to binary data (e.g. using a JSON encoder)
events = [
  %EventStore.EventData{
  	headers: serialize_to_json(%{user: "someuser@example.com"}),
    payload: serialize_to_json(%ExampleEvent{key: "value"})
  }
]

# append events to stream
{:ok, events} = EventStore.append_to_stream(stream_uuid, expected_version, events)
```

### Reading from a stream

```elixir
# read all events from the stream, starting at the beginning
{:ok, recorded_events} = EventStore.read_stream_forward(stream_uuid)
```

### Subscribe to all streams

Subscriptions to a stream will guarantee at least once delivery of every persisted event. Each subscription may be independently paused, then later resumed from where it stopped.

Events are received in batches after being persisted to storage. Each batch will contain events from a single stream only.

Receipt of each event, or batch, must be acknowledged by the subscriber. This allows the subscription to resume on failure without missing an event.

Subscriptions must be uniquely named and support a single subscriber. Attempting to connect two subscribers to the same subscription will return an error.


```elixir
# using an example subscriber
defmodule Subscriber do
  use GenServer

  def start_link do
    GenServer.start_link(__MODULE__, [])
  end

  def received_events(server) do
    GenServer.call(server, :received_events)
  end

  def init(events) do
    {:ok, %{events: events}}
  end

  def handle_info({:events, stream_uuid, stream_version, events}, state) do
    {:noreply, %{state | events: events ++ state.events}}
  end

  def handle_call(:received_events, _from, %{events: events} = state) do
    {:reply, events, state}
  end
end
```

```elixir
# create subscriber and subscribe to all streams
{:ok, subscriber} = Subscriber.start_link
{:ok, subscription} = EventStore.subscribe_to_all_streams("example_subscription", subscriber)
```

```elixir
# unsubscribe from a stream
{:ok, subscription} = EventStore.unsubscribe_from_all_streams("example_subscription")
```

## Benchmarking performance

Run the benchmark suite using mix with the `bench` environment, as configured in `config/bench.exs`. Logging is disabled for benchmarking.

```
MIX_ENV=bench mix do es.reset, app.start, bench
```

Example output:

```
## AppendEventsBench
append events, single writer                 100   10302.94 µs/op
append events, 10 concurrent writers          50   44910.74 µs/op
## ReadEventsBench
read events, single reader                  1000   1947.37 µs/op
read events, 10 concurrent readers           200   11314.01 µs/op
```
