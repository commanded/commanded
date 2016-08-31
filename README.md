# EventStore

CQRS Event Store implemented in Elixir. Uses [PostgreSQL](http://www.postgresql.org/) (v9.5 or later) as the underlying storage engine.

MIT License

[![Build Status](https://travis-ci.org/slashdotdash/eventstore.svg?branch=master)](https://travis-ci.org/slashdotdash/eventstore)

## Getting started

EventStore is [available in Hex](https://hex.pm/packages/eventstore) and can be installed as follows:

  1. Add eventstore to your list of dependencies in `mix.exs`:

    ```elixir    
    def deps do
      [{:eventstore, "~> 0.4.0"}]
    end
    ```

  2. Ensure `eventstore` is started before your application:

    ```elixir
    def application do
      [applications: [:eventstore]]
    end
    ```

  3. Add an `eventstore` config entry containing the PostgreSQL connection details to each environment's mix config file (e.g. `config/dev.exs`).

    ```elixir
    config :eventstore, EventStore.Storage,
      username: "postgres",
      password: "postgres",
      database: "eventstore_dev",
      hostname: "localhost"
    ```

  4. Create the EventStore database and tables using the `mix` task

    ```
    mix event_store.create
    ```

## Sample usage

Including `eventstore` in the applications section of `mix.exs` will ensure it is started.

```elixir
# manually start the EventStore supervisor
EventStore.Supervisor.start_link

# ... or ensure EventStore application is started
Application.ensure_all_started(:eventstore)
```

### Writing to a stream

```elixir
# create a unique identity for the stream (using the `uuid` package)
stream_uuid = UUID.uuid4

# a new stream will be created when the expected version is zero
expected_version = 0

# list of events to persist
events = [
  %EventStore.EventData{
    event_type: "ExampleEvent",
    data: %ExampleEvent{key: "value"},
    metadata: %{user: "someuser@example.com"},
  }
]

# append events to stream
:ok = EventStore.append_to_stream(stream_uuid, expected_version, events)
```

### Reading from a stream

```elixir
# read all events from the stream, starting at the stream's first event
{:ok, events} = EventStore.read_stream_forward(stream_uuid)
```

### Subscribe to all streams

Subscriptions to a stream will guarantee at least once delivery of every persisted event. Each subscription may be independently paused, then later resumed from where it stopped.

Events are received in batches after being persisted to storage. Each batch will contain events from a single stream only.

Receipt of each event, or batch, by the subscriber is acknowledged. This allows the subscription to resume on failure without missing an event.

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

  def handle_info({:events, events}, state) do
    {:noreply, %{state | events: events ++ state.events}}
  end

  def handle_call(:received_events, _from, %{events: events} = state) do
    {:reply, events, state}
  end
end
```

```elixir
# create your subscriber
{:ok, subscriber} = Subscriber.start_link

# subscribe to events appended to all streams
{:ok, subscription} = EventStore.subscribe_to_all_streams("example_subscription", subscriber)
```

```elixir
# unsubscribe from a stream
:ok = EventStore.unsubscribe_from_all_streams("example_subscription")
```

## Benchmarking performance

Run the benchmark suite using mix with the `bench` environment, as configured in `config/bench.exs`. Logging is disabled for benchmarking.

```
MIX_ENV=bench mix do es.reset, app.start, bench
```

Example output:

```
## AppendEventsBench
append events, single writer                  100   10170.26 µs/op
append events, 10 concurrent writers           20   85438.80 µs/op
append events, 100 concurrent writers           2   1102006.00 µs/op
## ReadEventsBench
read events, single reader                   1000   1578.10 µs/op
read events, 10 concurrent readers            100   16799.80 µs/op
read events, 100 concurrent readers            10   167397.30 µs/op
```

## Contributing

Pull requests to contribute new or improved features, and extend documentation are most welcome.

Please follow the existing coding conventions, or refer to the [Elixir style guide](https://github.com/niftyn8/elixir_style_guide).

You should include unit tests to cover any changes.
