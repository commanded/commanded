defmodule EventStore.Subscriptions.SubscribeToStream do
  use EventStore.StorageCase
  doctest EventStore.Subscriptions.Supervisor
  doctest EventStore.Subscriptions.Subscription

  alias EventStore.EventFactory
  alias EventStore.ProcessHelper
  alias EventStore.Storage.{Appender,Stream}
  alias EventStore.Streams
  alias EventStore.Subscriptions
  alias EventStore.Subscriber

  @all_stream "$all"
  @subscription_name "test_subscription"

  setup do
    storage_config = Application.get_env(:eventstore, EventStore.Storage)

    {:ok, conn} = Postgrex.start_link(storage_config)
    {:ok, %{conn: conn}}
  end

  @tag :wip
  test "subscribe to stream", %{conn: conn} do
    {:ok, stream_uuid, stream_id} = create_stream(conn)
    {:ok, persisted_events} = Appender.append(conn, stream_id, EventFactory.create_recorded_events(1, stream_id))

    {:ok, stream} = Streams.open_stream(stream_uuid)
    {:ok, subscriber} = Subscriber.start_link(self)
    {:ok, _} = Subscriptions.subscribe_to_stream(stream_uuid, stream, @subscription_name, subscriber)

    Subscriptions.notify_events(stream_uuid, persisted_events)

    assert_receive {:events, received_events}

    expected_received_events = EventFactory.deserialize_events(persisted_events)

    assert received_events == expected_received_events
    assert Subscriber.received_events(subscriber) == expected_received_events
  end

  test "subscribe to stream, ignore events from another stream", %{conn: conn} do
    {:ok, interested_stream_uuid, interested_stream_id} = create_stream(conn)
    {:ok, other_stream_uuid, other_stream_id} = create_stream(conn)

    {:ok, interested_persisted_events} = Appender.append(conn, interested_stream_id, EventFactory.create_recorded_events(1, interested_stream_id))
    {:ok, other_persisted_events} = Appender.append(conn, other_stream_id, EventFactory.create_recorded_events(1, other_stream_id, 2))

    {:ok, interested_stream} = Streams.open_stream(interested_stream_uuid)
    {:ok, subscriber} = Subscriber.start_link(self)
    {:ok, _} = Subscriptions.subscribe_to_stream(interested_stream_uuid, interested_stream, @subscription_name, subscriber)

    Subscriptions.notify_events(other_stream_uuid, other_persisted_events)

    expected_received_events = EventFactory.deserialize_events(interested_persisted_events)

    # received events should not include events from other stream
    assert_receive {:events, received_events}
    assert received_events == expected_received_events
    assert Subscriber.received_events(subscriber) == expected_received_events
  end

  test "subscribe to $all stream, receive events from all streams", %{conn: conn} do
    {:ok, stream1_uuid, stream1_id} = create_stream(conn)
    {:ok, stream2_uuid, stream2_id} = create_stream(conn)

    stream1_events = EventFactory.create_recorded_events(1, stream1_id)
    stream2_events = EventFactory.create_recorded_events(1, stream2_id, 2)

    {:ok, subscriber} = Subscriber.start_link(self)
    all_stream = Process.whereis(EventStore.Streams.AllStream)
    {:ok, _} = Subscriptions.subscribe_to_all_streams(all_stream, @subscription_name, subscriber)

    {:ok, stream1_persisted_events} = Appender.append(conn, stream1_id, stream1_events)
    {:ok, stream2_persisted_events} = Appender.append(conn, stream2_id, stream2_events)

    Subscriptions.notify_events(stream1_uuid, stream1_persisted_events)
    Subscriptions.notify_events(stream2_uuid, stream2_persisted_events)

    assert_receive {:events, stream1_received_events}
    assert_receive {:events, stream2_received_events}

    assert stream1_received_events == stream1_persisted_events
    assert stream2_received_events == stream2_persisted_events

    assert Subscriber.received_events(subscriber) == stream1_persisted_events ++ stream2_persisted_events
  end

  @tag :wip
  test "should monitor each subscription, terminate subscription and subscriber on error", %{conn: conn} do
    {:ok, stream_uuid, stream_id} = create_stream(conn)
    events = EventFactory.create_recorded_events(1, stream_id)

    {:ok, subscriber1} = Subscriber.start_link(self)
    {:ok, subscriber2} = Subscriber.start_link(self)

    all_stream = Process.whereis(EventStore.Streams.AllStream)

    {:ok, subscription1} = Subscriptions.subscribe_to_all_streams(all_stream, @subscription_name <> "1", subscriber1)
    {:ok, _} = Subscriptions.subscribe_to_all_streams(all_stream, @subscription_name <> "2", subscriber2)

    # unlink subscriber so we don't crash the test when it is terminated by the subscription shutdown
    Process.unlink(subscriber1)

    ProcessHelper.shutdown(subscription1)

    # should still notify subscription 2
    {:ok, persisted_events} = Appender.append(conn, stream_id, events)

    Subscriptions.notify_events(stream_uuid, persisted_events)

    # should kill subscription and subscriber
    assert Process.alive?(subscription1) == false
    assert Process.alive?(subscriber1) == false

    # subscription 2 should still receive events
    assert_receive {:events, received_events}

    assert received_events == persisted_events
    assert Subscriber.received_events(subscriber2) == persisted_events
  end

  defp create_stream(conn) do
    stream_uuid = UUID.uuid4
    {:ok, stream_id} = Stream.create_stream(conn, stream_uuid)
    {:ok, stream_uuid, stream_id}
  end
end
