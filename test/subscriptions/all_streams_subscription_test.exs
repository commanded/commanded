defmodule EventStore.Subscriptions.AllStreamsSubscriptionTest do
  use EventStore.StorageCase
  doctest EventStore.Subscriptions.AllStreamsSubscription

  alias EventStore.{EventFactory,Subscriber}
  alias EventStore.Storage.{Appender,Stream}
  alias EventStore.Subscriptions.AllStreamsSubscription

  @all_stream "$all"
  @subscription_name "test_subscription"

  setup do
    storage_config = Application.get_env(:eventstore, EventStore.Storage)

    {:ok, conn} = Postgrex.start_link(storage_config)
    {:ok, %{conn: conn}}
  end

  test "create subscription to stream" do
    subscription =
      AllStreamsSubscription.new
      |> AllStreamsSubscription.subscribe(@all_stream, nil, @subscription_name, nil, self)

    assert subscription.state == :catching_up
    assert subscription.data.subscription_name == @subscription_name
    assert subscription.data.subscriber == self
    assert subscription.data.last_seen_event_id == 0
  end

  test "catch-up subscription, no persisted events" do
    subscription =
      AllStreamsSubscription.new
      |> AllStreamsSubscription.subscribe(@all_stream, nil, @subscription_name, nil, self)
      |> AllStreamsSubscription.catch_up

    assert subscription.state == :subscribed
    assert subscription.data.last_seen_event_id == 0
  end

  test "catch-up subscription, unseen persisted events", %{conn: conn} do
    stream_uuid = UUID.uuid4
    {:ok, stream_id} = Stream.create_stream(conn, stream_uuid)
    recorded_events = EventFactory.create_recorded_events(3, stream_id)
    {:ok, 3} = Appender.append(conn, stream_id, recorded_events)

    subscription =
      AllStreamsSubscription.new
      |> AllStreamsSubscription.subscribe(@all_stream, nil, @subscription_name, nil, self)
      |> AllStreamsSubscription.catch_up

    assert subscription.state == :subscribed
    assert subscription.data.last_seen_event_id == 3

    assert_receive {:events, received_events, nil}
    expected_events = EventFactory.deserialize_events(recorded_events)

    assert pluck(received_events, :correlation_id) == pluck(expected_events, :correlation_id)
    assert pluck(received_events, :data) == pluck(expected_events, :data)
  end

  test "notify events" do
    events = EventFactory.create_recorded_events(1, 1)

    subscription =
      AllStreamsSubscription.new
      |> AllStreamsSubscription.subscribe(@all_stream, nil, @subscription_name, nil, self)
      |> AllStreamsSubscription.catch_up
      |> AllStreamsSubscription.notify_events(events)

    assert subscription.state == :subscribed

    assert_receive {:events, received_events, nil}

    assert pluck(received_events, :correlation_id) == pluck(events, :correlation_id)
    assert pluck(received_events, :data) == pluck(events, :data)
  end

  test "ack notified events", %{conn: conn} do
    stream_uuid = UUID.uuid4
    {:ok, stream_id} = Stream.create_stream(conn, stream_uuid)
    {:ok, 3} = Appender.append(conn, stream_id, EventFactory.create_recorded_events(3, stream_id))

    subscription =
      AllStreamsSubscription.new
      |> AllStreamsSubscription.subscribe(@all_stream, nil, @subscription_name, nil, self)
      |> AllStreamsSubscription.catch_up

    assert subscription.state == :subscribed

    assert_receive {:events, received_events, nil}
    assert length(received_events) == 3

    subscription =
      subscription
      |> AllStreamsSubscription.ack(3)

    assert subscription.state == :subscribed

    subscription =
      AllStreamsSubscription.new
      |> AllStreamsSubscription.subscribe(@all_stream, nil, @subscription_name, nil, self)
      |> AllStreamsSubscription.catch_up

    # should not receive already seen events
    refute_receive {:events, _received_events, nil}

    assert subscription.state == :subscribed
  end

  test "should replay events when not acknowledged", %{conn: conn} do
    stream_uuid = UUID.uuid4
    {:ok, stream_id} = Stream.create_stream(conn, stream_uuid)
    {:ok, 3} = Appender.append(conn, stream_id, EventFactory.create_recorded_events(3, stream_id))

    subscription =
      AllStreamsSubscription.new
      |> AllStreamsSubscription.subscribe(@all_stream, nil, @subscription_name, nil, self)
      |> AllStreamsSubscription.catch_up

    assert subscription.state == :subscribed

    assert_receive {:events, received_events, nil}
    assert length(received_events) == 3

    subscription =
      AllStreamsSubscription.new
      |> AllStreamsSubscription.subscribe(@all_stream, nil, @subscription_name, nil, self)
      |> AllStreamsSubscription.catch_up

    # should receive already seen events
    assert_receive {:events, received_events, nil}
    assert length(received_events) == 3

    assert subscription.state == :subscribed
  end

  test "should not notify events until ack received", %{conn: conn} do
    events = EventFactory.create_recorded_events(6, 1)
    initial_events = Enum.take(events, 3)
    remaining_events = Enum.drop(events, 3)

    subscription =
      AllStreamsSubscription.new
      |> AllStreamsSubscription.subscribe(@all_stream, nil, @subscription_name, nil, self)
      |> AllStreamsSubscription.catch_up
      |> AllStreamsSubscription.notify_events(initial_events)
      |> AllStreamsSubscription.notify_events(remaining_events)

    assert subscription.state == :subscribed

    # only receive initial events
    assert_receive {:events, received_events, nil}
    refute_receive {:events, _received_events, nil}

    assert length(received_events) == 3
    assert pluck(received_events, :correlation_id) == pluck(initial_events, :correlation_id)
    assert pluck(received_events, :data) == pluck(initial_events, :data)

     subscription =
       subscription
       |> AllStreamsSubscription.ack(3)

     # now receive all remaining events
     assert_receive {:events, received_events, nil}

     assert length(received_events) == 3
     assert pluck(received_events, :correlation_id) == pluck(remaining_events, :correlation_id)
     assert pluck(received_events, :data) == pluck(remaining_events, :data)
  end

  defp pluck(enumerable, field) do
    Enum.map(enumerable, &Map.get(&1, field))
  end
end
