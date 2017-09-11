# Subscriptions

Subscriptions to a stream will guarantee *at least once* delivery of every persisted event. Each subscription may be independently paused, then later resumed from where it stopped.

A subscription can be created to receive events published from a single logical stream or from all streams.

Events are received in batches after being persisted to storage. Each batch contains events from a single stream and for the same correlation id.

Subscriptions must be uniquely named and support a single subscriber. Attempting to connect two subscribers to the same subscription will return an error.

By default subscriptions are created from the single stream, or all stream, origin. So it will receive all events from the single stream, or all streams. You can optionally specify a given start position:

- `:origin` - subscribe to events from the start of the stream (identical to using 0). This is the current behaviour and will remain the default.
- `:current` - subscribe to events from the current version.
- `stream_version` or `event_id` (integer) - specify an exact stream version to subscribe from for a single stream subscription. You provide an event id for an all stream subscription.

## Ack received events

Receipt of each event by the subscriber must be acknowledged. This allows the subscription to resume on failure without missing an event.

The subscriber receives an `{:events, events}` tuple containing the published events. The subscription returned when subscribing to the stream should be used to send the `ack` to. This is achieved by the `EventStore.ack/2` function:

 ```elixir
 EventStore.ack(subscription, events)
 ```

A subscriber can confirm receipt of each event in a batch by sending multiple acks, one per event. The subscriber may confirm receipt of the last event in the batch in a single ack.

A subscriber will not receive further published events until it has confirmed receipt of all received events. This provides back pressure to the subscription to prevent the subscriber from being overwhelmed with messages if it cannot keep up. The subscription will buffer events until the subscriber is ready to receive, or an overflow occurs. At which point it will move into a catch-up mode and query events and replay them from storage until caught up.

### Subscribe to all events

Subscribe to events appended to all streams:

```elixir
{:ok, subscription} = EventStore.subscribe_to_all_streams("example_all_subscription", self())

receive do
  {:events, events} ->
    # ... process events & ack receipt
    EventStore.ack(subscription, events)
end
```

Unsubscribe from all streams:

```elixir
:ok = EventStore.unsubscribe_from_all_streams("example_all_subscription")
```

### Subscribe to single stream events

Subscribe to events appended to a *single* stream:

```elixir
stream_uuid = UUID.uuid4()
{:ok, subscription} = EventStore.subscribe_to_stream(stream_uuid, "example_single_subscription", self())

receive do
  {:events, events} ->
    # ... process events & ack receipt
    EventStore.ack(subscription, events)
end
```

Unsubscribe from a single stream:

```elixir
:ok = EventStore.unsubscribe_from_stream(stream_uuid, "example_single_subscription")
```

### Start subscription from a given position

You can choose to receive events from a given starting position.

The supported options are:

  - `:origin` - Start receiving events from the beginning of the stream or all streams.
  - `:current` - Subscribe to newly appended events only, skipping already persisted events.
  - `event_id` or `stream_version` - Provide the event id (all streams) of stream version (single stream) to begin receiving events from.

Example all stream subscription that will receive events appended after the subscription has been created:

```elixir
{:ok, subscription} = EventStore.subscribe_to_all_streams("example_subscription", self(), start_from: :current)
```

### Mapping events

You can provide an event mapping function that runs in the subscription process, before sending the event to your subscriber. You can use this to change the data received.

Subscribe to all streams and provide a `mapper` function that sends only the event data:

```elixir
{:ok, subscription} = EventStore.subscribe_to_all_streams("example_subscription", self(), mapper: fn %EventStore.RecordedEvent{data: data} -> {event_id, data} end)

receive do
  {:events, events} ->
    # ... process events & ack receipt using last `event_id`
    {event_id, _data} = List.last(events)

    EventStore.ack(subscription, event_id)
end
```

## Example subscriber

```elixir
# An example subscriber
defmodule Subscriber do
  use GenServer

  def start_link do
    GenServer.start_link(__MODULE__, [])
  end

  def received_events(subscriber) do
    GenServer.call(subscriber, :received_events)
  end

  def init(events) do
    # subscribe to events from all streams
    {:ok, subscription} = EventStore.subscribe_to_all_streams("example_subscription", self())

    {:ok, %{events: events, subscription: subscription}}
  end

  def handle_info({:events, events}, %{events: existing_events, subscription: subscription} = state) do
    # confirm receipt of received events
    EventStore.ack(subscription, events)

    {:noreply, %{state | events: existing_events ++ events}}
  end

  def handle_call(:received_events, _from, %{events: events} = state) do
    {:reply, events, state}
  end
end
```

Start your subscriber process, which subscribes to all streams in the event store.

```elixir
{:ok, subscriber} = Subscriber.start_link()
```
