# EventStore

CQRS event store implemented in Elixir. Uses [PostgreSQL](http://www.postgresql.org/) (v9.5 or later) as the underlying storage engine.

MIT License

[![Build Status](https://travis-ci.org/slashdotdash/eventstore.svg?branch=master)](https://travis-ci.org/slashdotdash/eventstore)

---

### Overview

- [Getting started](#getting-started)
- [Using the EventStore](#using-the-eventstore)
  - [Writing to a stream](#writing-to-a-stream)
  - [Reading from a stream](#reading-from-a-stream)
  - [Reading from all streams](#reading-from-all-streams)
  - [Stream from all streams](#stream-from-all-streams)
  - [Subscribe to streams](#subscribe-to-streams)
    - [Ack received events](#ack-received-events)
    - [Example subscriber](#example-subscriber)
- [Event serialization](#event-serialization)
- [Benchmarking performance](#benchmarking-performance)
- [Used in production?](#used-in-production)
- [Contributing](#contributing)
  - [Contributors](#contributors)

---

## Getting started

EventStore is [available in Hex](https://hex.pm/packages/eventstore) and can be installed as follows:

  1. Add eventstore to your list of dependencies in `mix.exs`:

    ```elixir    
    def deps do
      [{:eventstore, "~> 0.7"}]
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
      hostname: "localhost",
      pool_size: 10
    ```

  4. Create the EventStore database and tables using the `mix` task

    ```
    mix event_store.create
    ```

## Using the EventStore

### Writing to a stream

Create a unique identity for each stream. It **must** be a string. This example uses the [uuid](https://hex.pm/packages/uuid) package.

```elixir
stream_uuid = UUID.uuid4
```

Set the expected version of the stream. This is used for optimistic concurrency. A new stream will be created when the expected version is zero.

```elixir
expected_version = 0
```

Build a list of events to persist. The data and metadata fields will be serialized to binary data. This uses your own serializer, as defined in config, that implements the `EventStore.Serializer` behaviour.

```elixir
events = [
  %EventStore.EventData{
    event_type: "ExampleEvent",
    data: %ExampleEvent{key: "value"},
    metadata: %{user: "someuser@example.com"},
  }
]
```

Append the events to the stream.

```elixir
:ok = EventStore.append_to_stream(stream_uuid, expected_version, events)
```

### Reading from a stream

Read all events from the stream, starting at the stream's first event.

```elixir
{:ok, events} = EventStore.read_stream_forward(stream_uuid)
```

### Reading from all streams

Read all events from all streams.

```elixir
# defaults to reading the first 1,000 events from all streams
{:ok, events} = EventStore.read_all_streams_forward()
```

### Stream from all streams

Stream all events from all streams.

```elixir
events = EventStore.stream_all_forward() |> Enum.to_list
```

### Subscribe to streams

Subscriptions to a stream will guarantee at least once delivery of every persisted event. Each subscription may be independently paused, then later resumed from where it stopped. A subscription can be created to receive events published from a single logical stream or from all streams.

Events are received in batches after being persisted to storage. Each batch contains events from a single stream only and with the same correlation id.

Subscriptions must be uniquely named and support a single subscriber. Attempting to connect two subscribers to the same subscription will return an error.

By default subscriptions are created from the single stream, or all stream, origin. So it will receive all events from the single stream, or all streams. You can optionally specify a given start position.

- `:origin` - subscribe to events from the start of the stream (identical to using 0). This is the current behaviour and will remain the default.
- `:current` - subscribe to events from the current version.
- `stream_version` or `event_id` (integer) - specify an exact stream version to subscribe from for a single stream subscription. You provide an event id for an all stream subscription.

#### Ack received events

Receipt of each event by the subscriber must be acknowledged. This allows the subscription to resume on failure without missing an event.

The subscriber receives an `{:events, events, subscription}` tuple containing the published events and the subscription to send the `ack` to. This is achieved by sending an `{:ack, last_seen_event_id}` tuple to the `subscription` process. A subscriber can confirm receipt of each event in a batch by sending multiple acks, one per event. Or just confirm receipt of the last event in the batch.

A subscriber will not receive further published events until it has confirmed receipt of all received events. This provides back pressure to the subscription to prevent the subscriber from being overwhelmed with messages if it cannot keep up. The subscription will buffer events until the subscriber is ready to receive, or an overflow occurs. At which point it will move into a catch-up mode and query events and replay them from storage until caught up.

#### Example subscriber

```elixir
# An example subscriber
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

  def handle_info({:events, events, subscription}, state) do
    # confirm receipt of received events
    send(subscription, {:ack, List.last(events).event_id})

    {:noreply, %{state | events: state.events ++ events}}
  end

  def handle_call(:received_events, _from, %{events: events} = state) do
    {:reply, events, state}
  end
end
```

Create your subscriber.

```elixir
{:ok, subscriber} = Subscriber.start_link
```

Subscribe to events appended to all streams.

```elixir
{:ok, subscription} = EventStore.subscribe_to_all_streams("example_subscription", subscriber)
```

Unsubscribe from a stream.

```elixir
:ok = EventStore.unsubscribe_from_all_streams("example_subscription")
```

## Event serialization

The default serialization of event data and metadata uses Erlang's [external term format](http://erlang.org/doc/apps/erts/erl_ext_dist.html). This is not a recommended serialization format for deployment.

You must implement the `EventStore.Serializer` behaviour to provide your preferred serialization format. The example serializer below serializes event data to JSON using the [Poison](https://github.com/devinus/poison) library.

```elixir
defmodule JsonSerializer do
  @moduledoc """
  A serializer that uses the JSON format.
  """

  @behaviour EventStore.Serializer

  @doc """
  Serialize given term to JSON binary data.
  """
  def serialize(term) do
    Poison.encode!(term)
  end

  @doc """
  Deserialize given JSON binary data to the expected type.
  """
  def deserialize(binary, config) do
    type = case Keyword.get(config, :type, nil) do
      nil -> []
      type -> type |> String.to_existing_atom |> struct
    end
    Poison.decode!(binary, as: type)
  end
end
```

Configure your serializer by setting the `serializer` option in the mix environment configuration file (e.g. `config/dev.exs`).

```elixir
config :eventstore, EventStore.Storage,
  serializer: JsonSerializer,
  # ...
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

## Used in production?

Yes, this event store is being used in production.

PostgreSQL is used for the underlying storage. Providing guarantees to store data securely. It is ACID-compliant and transactional. PostgreSQL has a proven architecture. A strong reputation for reliability, data integrity, and correctness.

You can use any standard PostgreSQL tool to manage the event store data:

- [Backup and restore](https://www.postgresql.org/docs/current/static/backup-dump.html).
- [Continuous archiving and Point-in-Time Recovery (PITR)](https://www.postgresql.org/docs/current/static/continuous-archiving.html).

## Contributing

Pull requests to contribute new or improved features, and extend documentation are most welcome.

Please follow the existing coding conventions, or refer to the [Elixir style guide](https://github.com/niftyn8/elixir_style_guide).

You should include unit tests to cover any changes.

### Contributors

- [Andrey Akulov](https://github.com/astery)
- [Craig Savolainen](https://github.com/maedhr)
- [Paul Iannazzo](https://github.com/boxxxie)
- [Stuart Corbishley](https://github.com/stuartc)
