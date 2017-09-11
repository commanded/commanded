defmodule EventStore.Subscriptions.SingleStreamSubscriptionTest do
  use EventStore.StorageCase

  alias EventStore.{EventFactory,RecordedEvent,Streams}
  alias EventStore.Storage.{Appender,Stream}
  alias EventStore.Subscriptions.StreamSubscription

  @subscription_name "test_subscription"

  describe "subscribe to stream" do
    setup [:append_events_to_another_stream]

    test "create subscription to a single stream" do
      stream_uuid = UUID.uuid4()
      {:ok, _stream} = Streams.Supervisor.open_stream(stream_uuid)

      subscription = create_subscription(stream_uuid)

      assert subscription.state == :request_catch_up
      assert subscription.data.subscription_name == @subscription_name
      assert subscription.data.subscriber == self()
      assert subscription.data.last_seen == 0
      assert subscription.data.last_ack == 0
    end

    test "create subscription to a single stream from starting stream version" do
      stream_uuid = UUID.uuid4()
      {:ok, _stream} = Streams.Supervisor.open_stream(stream_uuid)

      subscription = create_subscription(stream_uuid, start_from_stream_version: 2)

      assert subscription.state == :request_catch_up
      assert subscription.data.subscription_name == @subscription_name
      assert subscription.data.subscriber == self()
      assert subscription.data.last_seen == 2
      assert subscription.data.last_ack == 2
    end

    test "create subscription to a single stream with event mapping function" do
      stream_uuid = UUID.uuid4()
      {:ok, _stream} = Streams.Supervisor.open_stream(stream_uuid)

      mapper = fn event -> event.event_id end
      subscription = create_subscription(stream_uuid, mapper: mapper)

      assert subscription.data.mapper == mapper
    end
  end

  describe "catch-up subscription" do
    setup [:append_events_to_another_stream, :create_stream]

    test "catch-up subscription, no persisted events" do
      stream_uuid = UUID.uuid4()
      {:ok, _stream} = Streams.Supervisor.open_stream(stream_uuid)

      subscription =
        stream_uuid
        |> create_subscription()
        |> StreamSubscription.catch_up()

      assert subscription.state == :catching_up
      assert subscription.data.last_seen == 0

      assert_receive_caught_up(0)
    end

    test "catch-up subscription, unseen persisted events", %{stream_uuid: stream_uuid, recorded_events: recorded_events} do
      subscription =
        stream_uuid
        |> create_subscription()
        |> StreamSubscription.catch_up()

      assert subscription.state == :catching_up
      assert subscription.data.last_seen == 0

      assert_receive {:events, received_events}
      subscription = ack(subscription, received_events)

      assert_receive_caught_up(3)

      expected_events = EventFactory.deserialize_events(recorded_events)

      assert pluck(received_events, :correlation_id) == pluck(expected_events, :correlation_id)
      assert pluck(received_events, :causation_id) == pluck(expected_events, :causation_id)
      assert pluck(received_events, :data) == pluck(expected_events, :data)

      assert subscription.data.last_ack == 3
    end

    test "confirm subscription caught up to persisted events", %{stream_uuid: stream_uuid} do
      subscription =
        stream_uuid
        |> create_subscription()
        |> StreamSubscription.catch_up()

      assert subscription.state == :catching_up
      assert subscription.data.last_seen == 0

      assert_receive {:events, received_events}
      subscription = ack(subscription, received_events)

      assert_receive_caught_up(3)

      subscription =
        subscription
        |> StreamSubscription.caught_up(3)

      assert subscription.state == :subscribed
      assert subscription.data.last_seen == 3
      assert subscription.data.last_ack == 3
    end
  end

  test "notify events" do
    stream_uuid = UUID.uuid4
    {:ok, _stream} = Streams.Supervisor.open_stream(stream_uuid)

    events = EventFactory.create_recorded_events(1, 1)

    subscription =
      create_subscription(stream_uuid)
      |> StreamSubscription.catch_up()
      |> StreamSubscription.caught_up(0)
      |> StreamSubscription.notify_events(events)

    assert subscription.state == :subscribed

    assert_receive {:events, received_events}

    assert pluck(received_events, :correlation_id) == pluck(events, :correlation_id)
    assert pluck(received_events, :causation_id) == pluck(events, :causation_id)
    assert pluck(received_events, :data) == pluck(events, :data)
  end

  describe "ack events" do
    setup [:append_events_to_another_stream, :create_stream, :create_subscription]

    test "should skip events during catch up when acknowledged", %{stream_uuid: stream_uuid, subscription: subscription, recorded_events: events} do
      subscription = ack(subscription, events)

      assert subscription.state == :subscribed
      assert subscription.data.last_seen == 3
      assert subscription.data.last_ack == 3

      subscription =
        stream_uuid
        |> create_subscription()
        |> StreamSubscription.catch_up()

      assert subscription.state == :catching_up

      # should not receive already seen events
      refute_receive {:events, _received_events}

      assert_receive_caught_up(3)
      subscription = StreamSubscription.caught_up(subscription, 3)

      assert subscription.state == :subscribed
      assert subscription.data.last_seen == 3
      assert subscription.data.last_ack == 3
    end

    test "should replay events when not acknowledged", %{stream_uuid: stream_uuid} do
      subscription =
        stream_uuid
        |> create_subscription()
        |> StreamSubscription.catch_up()

      assert subscription.state == :catching_up

      # should receive already seen, but not ack'd, events
      assert_receive {:events, received_events}
      assert length(received_events) == 3
      subscription = ack(subscription, received_events)

      assert_receive_caught_up(3)

      subscription = StreamSubscription.caught_up(subscription, 3)

      assert subscription.state == :subscribed
      assert subscription.data.last_seen == 3
      assert subscription.data.last_ack == 3
    end
  end

  # append events to another stream so that for single stream subscription tests the
  # event id does not match the stream version
  def append_events_to_another_stream(_context) do
    stream_uuid = UUID.uuid4()
    events = EventFactory.create_events(3)

    :ok = EventStore.append_to_stream(stream_uuid, 0, events)
  end

  defp create_stream(%{conn: conn}) do
    stream_uuid = UUID.uuid4
    {:ok, stream_id} = Stream.create_stream(conn, stream_uuid)

    recorded_events = EventFactory.create_recorded_events(3, stream_id, 4)
    {:ok, [4, 5, 6]} = Appender.append(conn, recorded_events)

    {:ok, stream} = Streams.Supervisor.open_stream(stream_uuid)

    [
      stream_uuid: stream_uuid,
      stream: stream,
      recorded_events: recorded_events,
    ]
  end

  defp create_subscription(%{stream_uuid: stream_uuid}) do
    subscription =
      stream_uuid
      |> create_subscription()
      |> StreamSubscription.catch_up()

    assert subscription.state == :catching_up

    assert_receive {:events, received_events}
    assert length(received_events) == 3

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

    {:ok, _stream} = Streams.Supervisor.open_stream(stream_uuid)

    subscription =
      stream_uuid
      |> create_subscription()
      |> StreamSubscription.catch_up()
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

    subscription = ack(subscription, received_events)

    assert subscription.state == :subscribed
    assert subscription.data.last_seen == 6
    assert subscription.data.last_ack == 3

   # now receive all remaining events
   assert_receive {:events, received_events}

   assert length(received_events) == 3
   assert pluck(received_events, :correlation_id) == pluck(remaining_events, :correlation_id)
   assert pluck(received_events, :causation_id) == pluck(remaining_events, :causation_id)
   assert pluck(received_events, :data) == pluck(remaining_events, :data)

   ack(subscription, received_events)
   refute_receive {:events, _received_events}
  end

  defp create_subscription(stream_uuid, opts \\ []) do
    StreamSubscription.new()
    |> StreamSubscription.subscribe(stream_uuid, @subscription_name, self(), opts)
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
