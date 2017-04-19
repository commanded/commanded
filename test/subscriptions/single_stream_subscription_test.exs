defmodule EventStore.Subscriptions.SingleStreamSubscriptionTest do
  use EventStore.StorageCase

  alias EventStore.EventFactory
  alias EventStore.Streams
  alias EventStore.Storage.{Appender,Stream}
  alias EventStore.Subscriptions.StreamSubscription

  @subscription_name "test_subscription"

  setup do
    storage_config = Application.get_env(:eventstore, EventStore.Storage)

    {:ok, conn} = Postgrex.start_link(storage_config)
    {:ok, %{conn: conn}}
  end

  describe "subscribe to stream" do
    test "create subscription to a single stream" do
      stream_uuid = UUID.uuid4()
      {:ok, stream} = Streams.open_stream(stream_uuid)

      subscription = create_subscription(stream_uuid, stream)

      assert subscription.state == :request_catch_up
      assert subscription.data.subscription_name == @subscription_name
      assert subscription.data.subscriber == self()
      assert subscription.data.last_seen == 0
      assert subscription.data.last_ack == 0
    end

    test "create subscription to a single stream from starting stream version" do
      stream_uuid = UUID.uuid4()
      {:ok, stream} = Streams.open_stream(stream_uuid)

      subscription = create_subscription(stream_uuid, stream, start_from_stream_version: 2)

      assert subscription.state == :request_catch_up
      assert subscription.data.subscription_name == @subscription_name
      assert subscription.data.subscriber == self()
      assert subscription.data.last_seen == 2
      assert subscription.data.last_ack == 2
    end

    test "create subscription to a single stream with event mapping function" do
      stream_uuid = UUID.uuid4()
      {:ok, stream} = Streams.open_stream(stream_uuid)

      mapper = fn event -> event.event_id end
      subscription = create_subscription(stream_uuid, stream, mapper: mapper)

      assert subscription.data.mapper == mapper
    end
  end

  describe "catch-up subscription" do
    test "catch-up subscription, no persisted events" do
      self = self()
      stream_uuid = UUID.uuid4()
      {:ok, stream} = Streams.open_stream(stream_uuid)

      subscription =
        stream_uuid
        |> create_subscription(stream)
        |> StreamSubscription.catch_up(fn last_seen -> send(self, {:caught_up, last_seen}) end)

      assert subscription.state == :catching_up
      assert subscription.data.last_seen == 0

      assert_receive {:caught_up, 0}
    end

    test "catch-up subscription, unseen persisted events", %{conn: conn} do
      self = self()
      stream_uuid = UUID.uuid4()
      {:ok, stream_id} = Stream.create_stream(conn, stream_uuid)
      recorded_events = EventFactory.create_recorded_events(3, stream_id)
      {:ok, 3} = Appender.append(conn, stream_id, recorded_events)

      {:ok, stream} = Streams.open_stream(stream_uuid)

      subscription =
        stream_uuid
        |> create_subscription(stream)
        |> StreamSubscription.catch_up(fn last_seen -> send(self, {:caught_up, last_seen}) end)

      assert subscription.state == :catching_up
      assert subscription.data.last_seen == 0

      assert_receive {:events, received_events}
      assert_receive {:caught_up, 3}

      expected_events = EventFactory.deserialize_events(recorded_events)

      assert pluck(received_events, :correlation_id) == pluck(expected_events, :correlation_id)
      assert pluck(received_events, :causation_id) == pluck(expected_events, :causation_id)
      assert pluck(received_events, :data) == pluck(expected_events, :data)
    end

    test "confirm subscription caught up to persisted events", %{conn: conn} do
      self = self()
      stream_uuid = UUID.uuid4
      {:ok, stream_id} = Stream.create_stream(conn, stream_uuid)
      recorded_events = EventFactory.create_recorded_events(3, stream_id)
      {:ok, 3} = Appender.append(conn, stream_id, recorded_events)

      {:ok, stream} = Streams.open_stream(stream_uuid)

      subscription =
        stream_uuid
        |> create_subscription(stream)
        |> StreamSubscription.catch_up(fn last_seen -> send(self, {:caught_up, last_seen}) end)

      assert subscription.state == :catching_up
      assert subscription.data.last_seen == 0

      assert_receive {:caught_up, last_seen}

      subscription =
        subscription
        |> StreamSubscription.caught_up(last_seen)

      assert subscription.state == :subscribed
      assert subscription.data.last_seen == 3
      assert subscription.data.last_ack == 0
    end
  end

  test "notify events" do
    stream_uuid = UUID.uuid4
    {:ok, stream} = Streams.open_stream(stream_uuid)

    events = EventFactory.create_recorded_events(1, 1)

    subscription =
      create_subscription(stream_uuid, stream)
      |> StreamSubscription.catch_up(fn last_seen -> last_seen end)
      |> StreamSubscription.caught_up(0)
      |> StreamSubscription.notify_events(events)

    assert subscription.state == :subscribed

    assert_receive {:events, received_events}

    assert pluck(received_events, :correlation_id) == pluck(events, :correlation_id)
    assert pluck(received_events, :causation_id) == pluck(events, :causation_id)
    assert pluck(received_events, :data) == pluck(events, :data)
  end

  describe "ack events" do
    setup [:create_stream, :create_subscription]

    test "ack notified events", %{stream_uuid: stream_uuid, stream: stream} do
      self = self()

      subscription =
        stream_uuid
        |> create_subscription(stream)
        |> StreamSubscription.catch_up(fn last_seen -> send(self, {:caught_up, last_seen}) end)

      assert subscription.state == :catching_up

      assert_receive {:caught_up, last_seen}

      subscription = StreamSubscription.caught_up(subscription, last_seen)

      assert subscription.state == :subscribed

      assert_receive {:events, received_events}
      assert length(received_events) == 3

      subscription =
        subscription
        |> StreamSubscription.ack(3)

      assert subscription.state == :subscribed
      assert subscription.data.last_seen == 3
      assert subscription.data.last_ack == 3

      # create subscription with no unseen events
      subscription =
        stream_uuid
        |> create_subscription(stream)
        |> StreamSubscription.catch_up(fn last_seen -> send(self, {:caught_up, last_seen}) end)

      assert subscription.state == :catching_up

      assert_receive {:caught_up, last_seen}

      # should not receive already seen events
      refute_receive {:events, _received_events}

      subscription = StreamSubscription.caught_up(subscription, last_seen)

      assert subscription.state == :subscribed
      assert subscription.data.last_seen == 3
      assert subscription.data.last_ack == 3
    end

    test "should replay events when not acknowledged", %{stream_uuid: stream_uuid, stream: stream} do
      self = self()

      subscription =
        stream_uuid
        |> create_subscription(stream)
        |> StreamSubscription.catch_up(fn last_seen -> send(self, {:caught_up, last_seen}) end)

      assert subscription.state == :catching_up

      # should receive already seen, but not ack'd, events
      assert_receive {:events, received_events}
      assert length(received_events) == 3

      assert_receive {:caught_up, last_seen}

      subscription = StreamSubscription.caught_up(subscription, last_seen)

      assert subscription.state == :subscribed
      assert subscription.data.last_seen == 3
      assert subscription.data.last_ack == 0
    end
  end

  defp create_stream(%{conn: conn}) do
    stream_uuid = UUID.uuid4
    {:ok, stream_id} = Stream.create_stream(conn, stream_uuid)
    {:ok, 3} = Appender.append(conn, stream_id, EventFactory.create_recorded_events(3, stream_id))

    {:ok, stream} = Streams.open_stream(stream_uuid)

    [stream_uuid: stream_uuid, stream: stream]
  end

  defp create_subscription(%{stream_uuid: stream_uuid, stream: stream}) do
    self = self()

    subscription =
      stream_uuid
      |> create_subscription(stream)
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

  test "should not notify events until ack received" do
    stream_uuid = UUID.uuid4
    events = EventFactory.create_recorded_events(6, 1)
    initial_events = Enum.take(events, 3)
    remaining_events = Enum.drop(events, 3)

    {:ok, stream} = Streams.open_stream(stream_uuid)

    subscription =
      stream_uuid
      |> create_subscription(stream)
      |> StreamSubscription.catch_up(fn last_seen -> last_seen end)
      |> StreamSubscription.caught_up(0)
      |> StreamSubscription.notify_events(initial_events)
      |> StreamSubscription.notify_events(remaining_events)

    assert subscription.data.last_seen == 6
    assert subscription.data.last_ack == 0

    # only receive initial events
    assert_receive {:events, received_events}
    refute_receive {:events, _received_events}

    assert length(received_events) == 3
    assert pluck(received_events, :correlation_id) == pluck(initial_events, :correlation_id)
    assert pluck(received_events, :causation_id) == pluck(initial_events, :causation_id)
    assert pluck(received_events, :data) == pluck(initial_events, :data)

    subscription =
      subscription
      |> StreamSubscription.ack(3)

    assert subscription.state == :subscribed
    assert subscription.data.last_seen == 6
    assert subscription.data.last_ack == 3

   # now receive all remaining events
   assert_receive {:events, received_events}

   assert length(received_events) == 3
   assert pluck(received_events, :correlation_id) == pluck(remaining_events, :correlation_id)
   assert pluck(received_events, :causation_id) == pluck(remaining_events, :causation_id)
   assert pluck(received_events, :data) == pluck(remaining_events, :data)
  end

  defp create_subscription(stream_uuid, stream, opts \\ []) do
    StreamSubscription.new()
    |> StreamSubscription.subscribe(stream_uuid, stream, @subscription_name, self(), opts)
  end

  defp pluck(enumerable, field) do
    Enum.map(enumerable, &Map.get(&1, field))
  end
end
