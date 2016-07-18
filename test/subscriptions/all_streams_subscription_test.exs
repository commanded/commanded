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
    {:ok, subscriber} = Subscriber.start_link(self)

    subscription =
      AllStreamsSubscription.new
      |> AllStreamsSubscription.subscribe(@all_stream, nil, @subscription_name, subscriber)

    assert subscription.state == :catching_up
    assert subscription.data.subscription_name == @subscription_name
    assert subscription.data.subscriber == subscriber
    assert subscription.data.last_seen_event_id == 0
  end

  test "catch-up subscription, no persisted events" do
    {:ok, subscriber} = Subscriber.start_link(self)

    subscription =
      AllStreamsSubscription.new
      |> AllStreamsSubscription.subscribe(@all_stream, nil, @subscription_name, subscriber)
      |> AllStreamsSubscription.catch_up

    assert subscription.state == :subscribed
    assert subscription.data.last_seen_event_id == 0
  end

  test "catch-up subscription, unseen persisted events", %{conn: conn} do
    stream_uuid = UUID.uuid4
    {:ok, stream_id} = Stream.create_stream(conn, stream_uuid)
    {:ok, subscriber} = Subscriber.start_link(self)
    recorded_events = EventFactory.create_recorded_events(3, stream_id)
    {:ok, 3} = Appender.append(conn, stream_id, recorded_events)

    subscription =
      AllStreamsSubscription.new
      |> AllStreamsSubscription.subscribe(@all_stream, nil, @subscription_name, subscriber)
      |> AllStreamsSubscription.catch_up

    assert subscription.state == :subscribed
    assert subscription.data.last_seen_event_id == 3

    assert_receive {:events, received_events}

    assert correlation_id(received_events) == correlation_id(recorded_events)
    assert data(received_events) == data(recorded_events)
  end

  test "notify events" do
    events = EventFactory.create_recorded_events(1, 1)
    {:ok, subscriber} = Subscriber.start_link(self)

    subscription =
      AllStreamsSubscription.new
      |> AllStreamsSubscription.subscribe(@all_stream, nil, @subscription_name, subscriber)
      |> AllStreamsSubscription.catch_up
      |> AllStreamsSubscription.notify_events(events)

    assert subscription.state == :subscribed

    assert_receive {:events, received_events}

    assert correlation_id(received_events) == correlation_id(events)
    assert data(received_events) == data(events)
  end

  test "ack notified events", %{conn: conn} do
    stream_uuid = UUID.uuid4
    {:ok, stream_id} = Stream.create_stream(conn, stream_uuid)
    {:ok, 3} = Appender.append(conn, stream_id, EventFactory.create_recorded_events(3, stream_id))

    {:ok, subscriber} = Subscriber.start_link(self)

    subscription =
      AllStreamsSubscription.new
      |> AllStreamsSubscription.subscribe(@all_stream, nil, @subscription_name, subscriber)
      |> AllStreamsSubscription.catch_up

    assert subscription.state == :subscribed

    assert_receive {:events, received_events}
    assert length(received_events) == 3

    subscription =
      AllStreamsSubscription.new
      |> AllStreamsSubscription.subscribe(@all_stream, nil, @subscription_name, subscriber)
      |> AllStreamsSubscription.catch_up

    # should not receive already seen events
    refute_receive {:events, _received_events}

    assert subscription.state == :subscribed
  end

  defp correlation_id(events), do: Enum.map(events, &(&1.correlation_id))
  defp data(events), do: Enum.map(events, &(&1.data))
end
