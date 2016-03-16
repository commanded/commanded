defmodule EventStore.Subscriptions.SubscribeToStream do
  use ExUnit.Case
  doctest EventStore.Subscriptions.Supervisor
  doctest EventStore.Subscriptions.Subscription

  alias EventStore.EventFactory
  alias EventStore.ProcessHelper
  alias EventStore.Storage
  alias EventStore.Subscriptions
  alias EventStore.Subscriber

  @all_stream "$all"
  @subscription_name "test_subscription"

  setup do
    {:ok, storage} = Storage.start_link
    :ok = Storage.reset!(storage)
    {:ok, subscriptions} = Subscriptions.start_link(storage)
    {:ok, storage: storage, subscriptions: subscriptions}
  end

  test "subscribe to stream", %{subscriptions: subscriptions} do
    stream_uuid = UUID.uuid4()
    events = EventFactory.create_recorded_events(1, stream_uuid)

    {:ok, subscriber} = Subscriber.start_link(self)
    {:ok, _subscription} = Subscriptions.subscribe_to_stream(subscriptions, stream_uuid, @subscription_name, subscriber)

    Subscriptions.notify_events(subscriptions, stream_uuid, events)

    assert_receive {:events, received_events}

    assert received_events == events
    assert Subscriber.received_events(subscriber) == events
  end

  test "subscribe to stream, ignore events from another stream", %{subscriptions: subscriptions} do
    interested_stream_uuid = UUID.uuid4()
    other_stream_uuid = UUID.uuid4()
    events = EventFactory.create_recorded_events(1, other_stream_uuid)

    {:ok, subscriber} = Subscriber.start_link(self)
    {:ok, _subscription} = Subscriptions.subscribe_to_stream(subscriptions, interested_stream_uuid, @subscription_name, subscriber)

    Subscriptions.notify_events(subscriptions, other_stream_uuid, events)

    refute_receive {:events, _received_events}

    assert Subscriber.received_events(subscriber) == []
  end

  test "subscribe to $all stream, receive events from all streams", %{subscriptions: subscriptions} do
    stream1_uuid = UUID.uuid4()
    stream2_uuid = UUID.uuid4()
    stream1_events = EventFactory.create_recorded_events(1, stream1_uuid)
    stream2_events = EventFactory.create_recorded_events(1, stream2_uuid)

    {:ok, subscriber} = Subscriber.start_link(self)
    {:ok, _subscription} = Subscriptions.subscribe_to_stream(subscriptions, @all_stream, @subscription_name, subscriber)

    Subscriptions.notify_events(subscriptions, stream1_uuid, stream1_events)
    Subscriptions.notify_events(subscriptions, stream2_uuid, stream2_events)

    assert_receive {:events, stream1_received_events}
    assert_receive {:events, stream2_received_events}

    assert stream1_received_events == stream1_events
    assert stream2_received_events == stream2_events

    assert Subscriber.received_events(subscriber) == stream1_events ++ stream2_events
  end

  test "should monitor each subscription, terminate single subscriber on error", %{subscriptions: subscriptions} do
    stream_uuid = UUID.uuid4()
    events = EventFactory.create_recorded_events(1, stream_uuid)

    {:ok, subscriber1} = Subscriber.start_link(self)
    {:ok, subscriber2} = Subscriber.start_link(self)

    {:ok, subscription1} = Subscriptions.subscribe_to_stream(subscriptions, stream_uuid, @subscription_name <> "1", subscriber1)
    {:ok, _subscription2} = Subscriptions.subscribe_to_stream(subscriptions, stream_uuid, @subscription_name <> "2", subscriber2)

    # unlink subscriber so we don't crash the test when it is terminated by the subscription shutdown
    Process.unlink(subscriber1)

    ProcessHelper.shutdown(subscription1)

    # should still notify subscription 2
    Subscriptions.notify_events(subscriptions, stream_uuid, events)

    # should kill subscription and subscriber
    assert Process.alive?(subscription1) == false
    assert Process.alive?(subscriber1) == false

    # subscription 2 should still receive events
    assert_receive {:events, received_events}

    assert received_events == events
    assert Subscriber.received_events(subscriber2) == events
  end
end
