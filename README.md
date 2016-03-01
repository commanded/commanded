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
# start the Storage process
{:ok, storage} = EventStore.Storage.start_link
```

### Writing to a stream

```elixir
# create a unique identity for the stream
stream_uuid = UUID.uuid4()

# a new stream will be created when the expected version is zero
expected_version = 0

# list of events to persist
events = [
  %EventStore.EventData{
  	headers: %{user: "someuser@example.com"},
    payload: %ExampleEvent{key: "value"}
  }
]

# append events to stream
{:ok, events} = EventStore.append_to_stream(storage, stream_uuid, expected_version, events)
```

### Reading from a stream

```elixir
# read all events from the stream, starting at the beginning (as from version is 0)
{:ok, recorded_events} = EventStore.read_stream_forward(storage, uuid, 0)
```

### Subscribe to all streams

Subscriptions are in progress, the usage will be further refined using a supervision tree.

#### Transient subscriptions

Events are received in batches after being persisted. Only events published while the subscription is active will be recevied.

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

  def handle_call(:received_events, _from, state) do
    result = state.events |> Enum.reverse
    {:reply, result, state}
  end
end
```

```elixir
# create subscriptions supervisor
{:ok, supervisor} = Subscriptions.Supervisor.start_link(storage)
{:ok, subscriptions} = Subscriptions.start_link(supervisor)
```

```elixir
# create subscriber and subscribe to all streams
{:ok, subscriber} = Subscriber.start_link
{:ok, subscription} = EventStore.subscribe_to_all_streams(subscriptions, "example_subscription", subscriber)
```

#### Persistent subscriptions (not yet implemented)

These will ensure at least once delivery of every persisted event. Each subscription may be independently paused, then later resume from where it stopped.

## Benchmarking performance

Run the benchmark suite using mix with the `bench` environment, as configured in `config/bench.exs`. Logging is disabled for benchmarking. 

```
MIX_ENV=bench mix do es.reset, app.start, bench
```

Example output:

```
## AppendEventsBench
append events, single writer         200   9738.10 µs/op
## ReadEventsBench
read events, single reader           500   3151.80 µs/op
```