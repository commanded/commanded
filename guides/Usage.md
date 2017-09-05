# Using the EventStore

## Writing to a stream

Create a unique identity for each stream. It **must** be a string. This example uses the [uuid](https://hex.pm/packages/uuid) package.

```elixir
stream_uuid = UUID.uuid4()
```

Set the expected version of the stream. This is used for optimistic concurrency. A new stream will be created when the expected version is zero.

```elixir
expected_version = 0
```

Build a list of events to persist. The data and metadata fields will be serialized to binary data. This uses your own serializer, as defined in config, that implements the `EventStore.Serializer` behaviour.

```elixir
events = [
  %EventStore.EventData{
    event_type: "Elixir.ExampleEvent",
    data: %ExampleEvent{key: "value"},
    metadata: %{user: "someuser@example.com"},
  }
]
```

Append the events to the stream:

```elixir
:ok = EventStore.append_to_stream(stream_uuid, expected_version, events)
```

## Reading from a stream

Read all events from a single stream, starting at the stream's first event:

```elixir
{:ok, events} = EventStore.read_stream_forward(stream_uuid)
```

## Reading from all streams

Read all events from all streams:

```elixir
{:ok, events} = EventStore.read_all_streams_forward()
```

By default this will be limited to read the first 1,000 events from all streams only.

## Stream from all streams

Stream all events from all streams:

```elixir
all_events = EventStore.stream_all_forward() |> Enum.to_list()
```

This will read *all* events into memory, it is for illustration only. Use the `Stream` functions to process the events in a memory efficient way.

Next: [Subscriptions](subscriptions.html)
