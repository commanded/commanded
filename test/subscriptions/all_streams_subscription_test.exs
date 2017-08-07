defmodule EventStore.Subscriptions.AllStreamsSubscriptionTest do
  use EventStore.StorageCase

  alias EventStore.EventFactory
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
    end

    test "create subscription to all streams from starting event id" do
      subscription = create_subscription(start_from_event_id: 2)

      assert subscription.state == :request_catch_up
      assert subscription.data.subscription_name == @subscription_name
      assert subscription.data.subscriber == self()
      assert subscription.data.last_seen == 2
      assert subscription.data.last_ack == 2
    end
  end

  test "catch-up subscription, no persisted events" do
    self = self()

    subscription =
      create_subscription()
      |> StreamSubscription.catch_up(fn last_seen -> send(self, {:caught_up, last_seen}) end)

    assert subscription.state == :catching_up
    assert_receive {:caught_up, 0}

    subscription = StreamSubscription.caught_up(subscription, 0)

    assert subscription.state == :subscribed
    assert subscription.data.last_seen == 0
  end

  test "catch-up subscription, unseen persisted events", %{conn: conn} do
    self = self()
    stream_uuid = UUID.uuid4
    {:ok, stream_id} = Stream.create_stream(conn, stream_uuid)
    recorded_events = EventFactory.create_recorded_events(3, stream_id)
    {:ok, 3} = Appender.append(conn, stream_id, recorded_events)

    subscription =
      create_subscription()
      |> StreamSubscription.catch_up(fn last_seen -> send(self, {:caught_up, last_seen}) end)

    assert subscription.state == :catching_up
    assert_receive {:caught_up, 3}

    subscription = StreamSubscription.caught_up(subscription, 3)

    assert subscription.state == :subscribed
    assert subscription.data.last_seen == 3

    assert_receive {:events, received_events}
    expected_events = EventFactory.deserialize_events(recorded_events)

    assert pluck(received_events, :correlation_id) == pluck(expected_events, :correlation_id)
    assert pluck(received_events, :causation_id) == pluck(expected_events, :causation_id)
    assert pluck(received_events, :data) == pluck(expected_events, :data)
  end

  test "notify events" do
    events = EventFactory.create_recorded_events(1, 1)

    subscription =
      create_subscription()
      |> StreamSubscription.catch_up(fn last_seen -> last_seen end)
      |> StreamSubscription.caught_up(0)
      |> StreamSubscription.notify_events(events)

    assert subscription.state == :subscribed

    assert_receive {:events, received_events}

    assert pluck(received_events, :correlation_id) == pluck(events, :correlation_id)
    assert pluck(received_events, :causation_id) == pluck(events, :causation_id)
    assert pluck(received_events, :data) == pluck(events, :data)
  end

  describe "ack notified events" do
    setup [:append_events_to_stream, :create_caught_up_subscription]

    test "should skip events during catch up when acknowledged", %{subscription: subscription} do
      self = self()
      subscription = StreamSubscription.ack(subscription, 3)

      assert subscription.state == :subscribed
      assert subscription.data.last_seen == 3
      assert subscription.data.last_ack == 3

      subscription =
        create_subscription()
        |> StreamSubscription.catch_up(fn last_seen -> send(self, {:caught_up, last_seen}) end)

      assert_receive {:caught_up, 3}

      # should not receive already seen events
      refute_receive {:events, _received_events}

      subscription = StreamSubscription.caught_up(subscription, 3)

      assert subscription.state == :subscribed
      assert subscription.data.last_seen == 3
      assert subscription.data.last_ack == 3
    end

    test "should replay events when catching up and events had not been acknowledged" do
      self = self()
      subscription =
        create_subscription()
        |> StreamSubscription.catch_up(fn last_seen -> send(self, {:caught_up, last_seen}) end)

      # should receive already seen events
      assert_receive {:events, received_events}
      assert length(received_events) == 3

      assert_receive {:caught_up, 3}

      subscription = StreamSubscription.caught_up(subscription, 3)

      assert subscription.state == :subscribed
      assert subscription.data.last_seen == 3
      assert subscription.data.last_ack == 0
    end

    def append_events_to_stream(%{conn: conn}) do
      stream_uuid = UUID.uuid4
      {:ok, stream_id} = Stream.create_stream(conn, stream_uuid)
      {:ok, 3} = Appender.append(conn, stream_id, EventFactory.create_recorded_events(3, stream_id))

      []
    end

    def create_caught_up_subscription(_context) do
      self = self()

      subscription =
        create_subscription()
        |> StreamSubscription.catch_up(fn last_seen -> send(self, {:caught_up, last_seen}) end)

      assert subscription.state == :catching_up

      assert_receive {:events, received_events}
      assert length(received_events) == 3

      assert_receive {:caught_up, 3}

      subscription = StreamSubscription.caught_up(subscription, 3)

      assert subscription.state == :subscribed
      assert subscription.data.last_seen == 3
      assert subscription.data.last_ack == 0

      [subscription: subscription]
    end
  end

  test "should not notify events until ack received" do
    events = EventFactory.create_recorded_events(6, 1)
    initial_events = Enum.take(events, 3)
    remaining_events = Enum.drop(events, 3)

    subscription =
      create_subscription()
      |> StreamSubscription.catch_up(fn last_seen -> last_seen end)
      |> StreamSubscription.caught_up(0)
      |> StreamSubscription.notify_events(initial_events)
      |> StreamSubscription.notify_events(remaining_events)

    assert subscription.state == :subscribed

    # only receive initial events
    assert_receive {:events, received_events}
    refute_receive {:events, _received_events}

    assert length(received_events) == 3
    assert pluck(received_events, :correlation_id) == pluck(initial_events, :correlation_id)
    assert pluck(received_events, :causation_id) == pluck(initial_events, :causation_id)
    assert pluck(received_events, :data) == pluck(initial_events, :data)

    # don't receive remaining events until ack received for all initial events
    subscription = ack_refute_receive(subscription, 1)
    subscription = ack_refute_receive(subscription, 2)

    subscription =
      subscription
      |> StreamSubscription.ack(3)

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
      events = EventFactory.create_recorded_events(6, 1)
      initial_events = Enum.take(events, 3)
      remaining_events = Enum.drop(events, 3)

      subscription =
        create_subscription(max_size: 3)
        |> StreamSubscription.catch_up(fn last_seen -> last_seen end)
        |> StreamSubscription.caught_up(0)
        |> StreamSubscription.notify_events(initial_events)
        |> StreamSubscription.notify_events(remaining_events)

      assert subscription.state == :max_capacity

      assert_receive {:events, received_events}
      refute_receive {:events, _received_events}

      assert length(received_events) == 3
      assert pluck(received_events, :correlation_id) == pluck(initial_events, :correlation_id)
      assert pluck(received_events, :causation_id) == pluck(initial_events, :causation_id)
      assert pluck(received_events, :data) == pluck(initial_events, :data)

      subscription = StreamSubscription.ack(subscription, 3)

      assert subscription.state == :request_catch_up

      # now receive all remaining events
      assert_receive {:events, received_events}

      assert length(received_events) == 3
      assert pluck(received_events, :correlation_id) == pluck(remaining_events, :correlation_id)
      assert pluck(received_events, :causation_id) == pluck(remaining_events, :causation_id)
      assert pluck(received_events, :data) == pluck(remaining_events, :data)
    end

    test "should receive pending events on ack after reaching max capacity" do
      events = EventFactory.create_recorded_events(6, 1)
      initial_events = Enum.take(events, 3)
      remaining_events = Enum.drop(events, 3)

      subscription =
        create_subscription(max_size: 3)
        |> StreamSubscription.catch_up(fn last_seen -> last_seen end)
        |> StreamSubscription.caught_up(0)
        |> StreamSubscription.notify_events(initial_events)
        |> StreamSubscription.notify_events(remaining_events)

      assert subscription.state == :max_capacity

      subscription = StreamSubscription.ack(subscription, 1)

      assert subscription.state == :max_capacity

      assert_receive {:events, received_events}
      refute_receive {:events, _received_events}

      assert length(received_events) == 3

      subscription = StreamSubscription.ack(subscription, 2)

      assert subscription.state == :max_capacity

      subscription = StreamSubscription.ack(subscription, 3)

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
    StreamSubscription.new
    |> StreamSubscription.subscribe(@all_stream, @subscription_name, self(), opts)
  end

  defp ack_refute_receive(subscription, ack) do
    subscription = StreamSubscription.ack(subscription, ack)

    assert subscription.state == :subscribed
    assert subscription.data.last_seen == 6
    assert subscription.data.last_ack == ack

    # don't receive remaining events until ack received for all initial events
    refute_receive {:events, _received_events}

    subscription
  end

  defp pluck(enumerable, field) do
    Enum.map(enumerable, &Map.get(&1, field))
  end
end
