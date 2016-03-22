defmodule EventStore.Subscriptions.SubscribeToStream do
  use EventStore.StorageCase
  doctest EventStore.Subscriptions.Supervisor
  doctest EventStore.Subscriptions.Subscription

  alias EventStore.EventFactory
  alias EventStore.ProcessHelper
  alias EventStore.Storage
  alias EventStore.Subscriptions
  alias EventStore.Subscriber

  @all_stream "$all"
  @subscription_name "test_subscription"

  test "subscribe to stream" do
    stream_uuid = UUID.uuid4()
    events = EventFactory.create_events(1)

    {:ok, persisted_events} = Storage.append_to_stream(stream_uuid, 0, events)

    {:ok, subscriber} = Subscriber.start_link(self)
    {:ok, _subscription} = Subscriptions.subscribe_to_stream(stream_uuid, @subscription_name, subscriber)

    Subscriptions.notify_events(stream_uuid, persisted_events)

    assert_receive {:events, received_events}

    assert received_events == persisted_events
    assert Subscriber.received_events(subscriber) == persisted_events
  end

  test "subscribe to stream, ignore events from another stream" do
    interested_stream_uuid = UUID.uuid4()
    other_stream_uuid = UUID.uuid4()
    events = EventFactory.create_events(1)

    {:ok, persisted_events} = Storage.append_to_stream(interested_stream_uuid, 0, events)
    {:ok, other_persisted_events} = Storage.append_to_stream(other_stream_uuid, 0, events)

    {:ok, subscriber} = Subscriber.start_link(self)
    {:ok, _subscription} = Subscriptions.subscribe_to_stream(interested_stream_uuid, @subscription_name, subscriber)

    Subscriptions.notify_events(other_stream_uuid, other_persisted_events)

    # received events does not include events from other stream
    assert_receive {:events, received_events}
    assert Subscriber.received_events(subscriber) == persisted_events
  end

  test "subscribe to $all stream, receive events from all streams" do
    stream1_uuid = UUID.uuid4()
    stream2_uuid = UUID.uuid4()
    stream1_events = EventFactory.create_events(1)
    stream2_events = EventFactory.create_events(1)

    {:ok, subscriber} = Subscriber.start_link(self)
    {:ok, _subscription} = Subscriptions.subscribe_to_stream(@all_stream, @subscription_name, subscriber)

    {:ok, stream1_persisted_events} = Storage.append_to_stream(stream1_uuid, 0, stream1_events)
    {:ok, stream2_persisted_events} = Storage.append_to_stream(stream2_uuid, 0, stream2_events)

    Subscriptions.notify_events(stream1_uuid, stream1_persisted_events)
    Subscriptions.notify_events(stream2_uuid, stream2_persisted_events)

    assert_receive {:events, stream1_received_events}
    assert_receive {:events, stream2_received_events}

    assert stream1_received_events == stream1_persisted_events
    assert stream2_received_events == stream2_persisted_events

    assert Subscriber.received_events(subscriber) == stream1_persisted_events ++ stream2_persisted_events
  end

  test "should monitor each subscription, terminate subscription and subscriber on error" do
    stream_uuid = UUID.uuid4()
    events = EventFactory.create_events(1)

    {:ok, subscriber1} = Subscriber.start_link(self)
    {:ok, subscriber2} = Subscriber.start_link(self)

    {:ok, subscription1} = Subscriptions.subscribe_to_stream(@all_stream, @subscription_name <> "1", subscriber1)
    {:ok, _subscription2} = Subscriptions.subscribe_to_stream(@all_stream, @subscription_name <> "2", subscriber2)

    # unlink subscriber so we don't crash the test when it is terminated by the subscription shutdown
    Process.unlink(subscriber1)

    ProcessHelper.shutdown(subscription1)

    # should still notify subscription 2
    {:ok, persisted_events} = Storage.append_to_stream(stream_uuid, 0, events)

    Subscriptions.notify_events(stream_uuid, persisted_events)

    # should kill subscription and subscriber
    assert Process.alive?(subscription1) == false
    assert Process.alive?(subscriber1) == false

    # subscription 2 should still receive events
    assert_receive {:events, received_events}

    assert received_events == persisted_events
    assert Subscriber.received_events(subscriber2) == persisted_events
  end
end
