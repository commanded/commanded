defmodule EventStore.Subscriptions.AllStreamsSubscriptionTest do
  use EventStore.StorageCase

  alias EventStore.{EventFactory,RecordedEvent}
  alias EventStore.Storage.{Appender,Stream}
  alias EventStore.Subscriptions.StreamSubscription

  @all_stream "$all"
  @subscription_name "test_subscription"

  describe "subscribe to all streams" do
    test "create subscription to all streams" do
      subscription = create_subscription()

      assert subscription.state == :request_catch_up
      assert subscription.data.subscription_name == @subscription_name
      assert subscription.data.subscriber == self()
      assert subscription.data.last_seen == 0
      assert subscription.data.last_ack == 0
      assert subscription.data.last_received == nil
    end

    test "create subscription to all streams from starting event id" do
      subscription = create_subscription(start_from_event_id: 2)

      assert subscription.state == :request_catch_up
      assert subscription.data.subscription_name == @subscription_name
      assert subscription.data.subscriber == self()
      assert subscription.data.last_seen == 2
      assert subscription.data.last_ack == 2
      assert subscription.data.last_received == nil
    end
  end

  test "catch-up subscription, no persisted events" do
    subscription =
      create_subscription()
      |> StreamSubscription.catch_up()

    assert subscription.state == :catching_up
    assert_receive_caught_up(0)

    subscription = StreamSubscription.caught_up(subscription, 0)

    assert subscription.state == :subscribed
    assert subscription.data.last_seen == 0
    assert subscription.data.last_received == nil
  end

  test "catch-up subscription, unseen persisted events", %{conn: conn} do
    stream_uuid = UUID.uuid4
    {:ok, stream_id} = Stream.create_stream(conn, stream_uuid)
    recorded_events = EventFactory.create_recorded_events(3, stream_uuid)
    {:ok, [1, 2, 3]} = Appender.append(conn, stream_id, recorded_events)

    subscription =
      create_subscription()
      |> StreamSubscription.catch_up()

    assert subscription.state == :catching_up

    assert_receive {:events, received_events}
    subscription = ack(subscription, received_events)

    subscription = StreamSubscription.caught_up(subscription, 3)
    assert_receive_caught_up(3)

    assert subscription.state == :subscribed
    assert subscription.data.last_seen == 3
    assert subscription.data.last_received == nil

    expected_events = EventFactory.deserialize_events(recorded_events)

    assert pluck(received_events, :correlation_id) == pluck(expected_events, :correlation_id)
    assert pluck(received_events, :causation_id) == pluck(expected_events, :causation_id)
    assert pluck(received_events, :data) == pluck(expected_events, :data)
  end

  test "notify events" do
    stream_uuid = UUID.uuid4()
    events = EventFactory.create_recorded_events(1, stream_uuid)

    subscription =
      create_subscription()
      |> StreamSubscription.catch_up()
      |> StreamSubscription.caught_up(0)
      |> StreamSubscription.notify_events(events)

    assert subscription.state == :subscribed
    assert subscription.data.last_received == 1

    assert_receive {:events, received_events}

    assert pluck(received_events, :correlation_id) == pluck(events, :correlation_id)
    assert pluck(received_events, :causation_id) == pluck(events, :causation_id)
    assert pluck(received_events, :data) == pluck(events, :data)
  end

  test "should catch up when events received while catching up" do
    subscription =
      create_subscription()
      |> StreamSubscription.catch_up()

    assert subscription.state == :catching_up
    assert_receive_caught_up(0)

    stream_uuid = UUID.uuid4()
    recorded_events = EventFactory.create_recorded_events(3, stream_uuid)

    # notify events while subscription is catching up
    subscription = StreamSubscription.notify_events(subscription, recorded_events)

    subscription = StreamSubscription.caught_up(subscription, 0)

    assert subscription.state == :request_catch_up
    assert subscription.data.last_received == 3
    assert subscription.data.last_seen == 0
    assert subscription.data.last_received == 3
  end

  describe "ack notified events" do
    setup [:append_events_to_stream, :create_caught_up_subscription]

    test "should skip events during catch up when acknowledged", %{subscription: subscription, recorded_events: events} do
      subscription = ack(subscription, events)

      assert subscription.state == :subscribed
      assert subscription.data.last_seen == 3
      assert subscription.data.last_ack == 3
      assert subscription.data.last_received == nil

      subscription =
        create_subscription()
        |> StreamSubscription.catch_up()

      assert_receive_caught_up(3)

      # should not receive already seen events
      refute_receive {:events, _received_events}

      subscription = StreamSubscription.caught_up(subscription, 3)

      assert subscription.state == :subscribed
      assert subscription.data.last_seen == 3
      assert subscription.data.last_ack == 3
      assert subscription.data.last_received == nil
    end

    test "should replay events when catching up and events had not been acknowledged" do
      subscription =
        create_subscription()
        |> StreamSubscription.catch_up()

      # should receive already seen events
      assert_receive {:events, received_events}
      assert length(received_events) == 3

      subscription = ack(subscription, received_events)
      assert_receive_caught_up(3)

      subscription = StreamSubscription.caught_up(subscription, 3)

      assert subscription.state == :subscribed
      assert subscription.data.last_seen == 3
      assert subscription.data.last_ack == 3
      assert subscription.data.last_received == nil
    end

    def append_events_to_stream(%{conn: conn}) do
      stream_uuid = UUID.uuid4
      {:ok, stream_id} = Stream.create_stream(conn, stream_uuid)

      recorded_events = EventFactory.create_recorded_events(3, stream_uuid)
      {:ok, [1, 2, 3]} = Appender.append(conn, stream_id, recorded_events)

      [recorded_events: recorded_events]
    end

    def create_caught_up_subscription(_context) do
      subscription =
        create_subscription()
        |> StreamSubscription.catch_up()

      assert subscription.state == :catching_up

      assert_receive {:events, received_events}
      assert length(received_events) == 3

      subscription = StreamSubscription.caught_up(subscription, 3)

      assert subscription.state == :subscribed
      assert subscription.data.last_seen == 3
      assert subscription.data.last_ack == 0
      assert subscription.data.last_received == nil

      [subscription: subscription]
    end
  end

  test "should not notify events until ack received" do
    stream_uuid = UUID.uuid4
    events = EventFactory.create_recorded_events(6, stream_uuid)
    initial_events = Enum.take(events, 3)
    remaining_events = Enum.drop(events, 3)

    subscription =
      create_subscription()
      |> StreamSubscription.catch_up()
      |> StreamSubscription.caught_up(0)
      |> StreamSubscription.notify_events(initial_events)
      |> StreamSubscription.notify_events(remaining_events)

    assert subscription.state == :subscribed
    assert subscription.data.last_received == 6

    # only receive initial events
    assert_receive {:events, received_events}
    refute_receive {:events, _received_events}

    assert length(received_events) == 3
    assert pluck(received_events, :correlation_id) == pluck(initial_events, :correlation_id)
    assert pluck(received_events, :causation_id) == pluck(initial_events, :causation_id)
    assert pluck(received_events, :data) == pluck(initial_events, :data)

    [event1, event2, _event3] = received_events

    # don't receive remaining events until ack received for all initial events
    subscription = ack_refute_receive(subscription, event1, 1)
    subscription = ack_refute_receive(subscription, event2, 2)

    subscription = ack(subscription, received_events)

    assert subscription.state == :subscribed

    # now receive all remaining events
    assert_receive {:events, received_events}

    assert length(received_events) == 3
    assert pluck(received_events, :correlation_id) == pluck(remaining_events, :correlation_id)
    assert pluck(received_events, :causation_id) == pluck(remaining_events, :causation_id)
    assert pluck(received_events, :data) == pluck(remaining_events, :data)
  end

  describe "pending event buffer limit" do
    test "should restrict pending events until ack" do
      stream_uuid = UUID.uuid4
      events = EventFactory.create_recorded_events(6, stream_uuid)
      initial_events = Enum.take(events, 3)
      remaining_events = Enum.drop(events, 3)

      subscription =
        create_subscription(max_size: 3)
        |> StreamSubscription.catch_up()
        |> StreamSubscription.caught_up(0)
        |> StreamSubscription.notify_events(initial_events)
        |> StreamSubscription.notify_events(remaining_events)

      assert subscription.state == :max_capacity
      assert subscription.data.last_received == 6

      assert_receive {:events, received_events}
      refute_receive {:events, _received_events}

      assert length(received_events) == 3
      assert pluck(received_events, :correlation_id) == pluck(initial_events, :correlation_id)
      assert pluck(received_events, :causation_id) == pluck(initial_events, :causation_id)
      assert pluck(received_events, :data) == pluck(initial_events, :data)

      subscription = ack(subscription, initial_events)

      assert subscription.state == :request_catch_up

      # now receive all remaining events
      assert_receive {:events, received_events}

      assert length(received_events) == 3
      assert pluck(received_events, :correlation_id) == pluck(remaining_events, :correlation_id)
      assert pluck(received_events, :causation_id) == pluck(remaining_events, :causation_id)
      assert pluck(received_events, :data) == pluck(remaining_events, :data)
    end

    test "should receive pending events on ack after reaching max capacity" do
      stream_uuid = UUID.uuid4
      events = EventFactory.create_recorded_events(6, stream_uuid)
      initial_events = Enum.take(events, 3)
      remaining_events = Enum.drop(events, 3)

      subscription =
        create_subscription(max_size: 3)
        |> StreamSubscription.catch_up()
        |> StreamSubscription.caught_up(0)
        |> StreamSubscription.notify_events(initial_events)
        |> StreamSubscription.notify_events(remaining_events)

      assert subscription.state == :max_capacity
      assert subscription.data.last_received == 6

      subscription = ack(subscription, hd(initial_events))

      assert subscription.state == :max_capacity

      assert_receive {:events, received_events}
      refute_receive {:events, _received_events}

      assert length(received_events) == 3

      subscription = ack(subscription, Enum.take(received_events, 2))

      assert subscription.state == :max_capacity

      subscription = ack(subscription, List.last(received_events))

      assert subscription.state == :request_catch_up

      # now receive all remaining events
      assert_receive {:events, received_events}

      assert length(received_events) == 3
      assert pluck(received_events, :correlation_id) == pluck(remaining_events, :correlation_id)
      assert pluck(received_events, :causation_id) == pluck(remaining_events, :causation_id)
      assert pluck(received_events, :data) == pluck(remaining_events, :data)
    end
  end

  defp create_subscription(opts \\ []) do
    StreamSubscription.new()
    |> StreamSubscription.subscribe(@all_stream, @subscription_name, self(), opts)
  end

  defp ack_refute_receive(subscription, ack, expected_last_ack) do
    subscription = ack(subscription, ack)

    assert subscription.state == :subscribed
    assert subscription.data.last_seen == 6
    assert subscription.data.last_ack == expected_last_ack
    assert subscription.data.last_received == 6

    # don't receive remaining events until ack received for all initial events
    refute_receive {:events, _received_events}

    subscription
  end

  def ack(subscription, events) when is_list(events) do
    ack(subscription, List.last(events))
  end

  def ack(subscription, %RecordedEvent{event_id: event_id, stream_version: stream_version}) do
    StreamSubscription.ack(subscription, {event_id, stream_version})
  end

  defp assert_receive_caught_up(to) do
    assert_receive {:"$gen_cast", {:caught_up, ^to}}
  end

  defp pluck(enumerable, field) do
    Enum.map(enumerable, &Map.get(&1, field))
  end
end
