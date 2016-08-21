defmodule EventStore.Subscriptions.SubscribeToStream do
  use EventStore.StorageCase
  doctest EventStore.Subscriptions.Supervisor
  doctest EventStore.Subscriptions.Subscription

  alias EventStore.{EventFactory,ProcessHelper}
  alias EventStore.Storage.{Appender,Reader,Stream}
  alias EventStore.{Streams,Subscriptions,Subscriber}

  @all_stream "$all"
  @subscription_name "test_subscription"
  @receive_timeout 1_000

  setup do
    storage_config = Application.get_env(:eventstore, EventStore.Storage)

    {:ok, conn} = Postgrex.start_link(storage_config)
    {:ok, %{conn: conn}}
  end

  test "subscribe to single stream", %{conn: conn} do
    {:ok, stream_uuid, stream_id} = create_stream(conn)
    {:ok, stream} = Streams.open_stream(stream_uuid)
    {:ok, _} = Subscriptions.subscribe_to_stream(stream_uuid, stream, @subscription_name, self)

    {:ok, persisted_events} = notify_events(conn, stream_id, stream_uuid)

    assert_receive {:events, received_events}, @receive_timeout
    assert received_events == EventFactory.deserialize_events(persisted_events)
  end

  test "subscribe to stream more than once using same subscription name should error", %{conn: conn} do
    {:ok, stream_uuid, _stream_id} = create_stream(conn)
    {:ok, stream} = Streams.open_stream(stream_uuid)

    {:ok, _} = Subscriptions.subscribe_to_stream(stream_uuid, stream, @subscription_name, self)
    {:error, :subscription_already_exists} = Subscriptions.subscribe_to_stream(stream_uuid, stream, @subscription_name, self)
  end

  test "subscribe to single stream should ignore events from another stream", %{conn: conn} do
    {:ok, interested_stream_uuid, interested_stream_id} = create_stream(conn)
    {:ok, other_stream_uuid, other_stream_id} = create_stream(conn)

    {:ok, 1} = Appender.append(conn, interested_stream_id, EventFactory.create_recorded_events(1, interested_stream_id))
    {:ok, 1} = Appender.append(conn, other_stream_id, EventFactory.create_recorded_events(1, other_stream_id, 2))

    {:ok, interested_stream} = Streams.open_stream(interested_stream_uuid)
    {:ok, _} = Subscriptions.subscribe_to_stream(interested_stream_uuid, interested_stream, @subscription_name, self)

    {:ok, interested_persisted_events} = Reader.read_forward(conn, interested_stream_id, 0)
    {:ok, other_persisted_events} = Reader.read_forward(conn, other_stream_id, 0)

    Subscriptions.notify_events(other_stream_uuid, other_persisted_events)

    expected_received_events = EventFactory.deserialize_events(interested_persisted_events)

    # received events should not include events from other stream
    assert_receive {:events, received_events}, @receive_timeout
    assert received_events == expected_received_events
  end

  test "subscribe to all streams should receive events from all streams", %{conn: conn} do
    {:ok, stream1_uuid, stream1_id} = create_stream(conn)
    {:ok, stream2_uuid, stream2_id} = create_stream(conn)

    stream1_events = EventFactory.create_recorded_events(1, stream1_id)
    stream2_events = EventFactory.create_recorded_events(1, stream2_id, 2)

    all_stream = Process.whereis(EventStore.Streams.AllStream)
    {:ok, _} = Subscriptions.subscribe_to_all_streams(all_stream, @subscription_name, self)

    {:ok, 1} = Appender.append(conn, stream1_id, stream1_events)
    {:ok, 1} = Appender.append(conn, stream2_id, stream2_events)

    {:ok, stream1_persisted_events} = Reader.read_forward(conn, stream1_id, 0)
    {:ok, stream2_persisted_events} = Reader.read_forward(conn, stream2_id, 0)

    Subscriptions.notify_events(stream1_uuid, stream1_persisted_events)
    Subscriptions.notify_events(stream2_uuid, stream2_persisted_events)

    assert_receive {:events, stream1_received_events}, @receive_timeout
    assert_receive {:events, stream2_received_events}, @receive_timeout

    assert stream1_received_events == EventFactory.deserialize_events(stream1_persisted_events)
    assert stream2_received_events == EventFactory.deserialize_events(stream2_persisted_events)
  end

  test "should monitor all stream subscription, terminate subscription and subscriber on error", %{conn: conn} do
    {:ok, stream_uuid, stream_id} = create_stream(conn)
    events = EventFactory.create_recorded_events(1, stream_id)

    {:ok, subscriber1} = Subscriber.start_link(self)
    {:ok, subscriber2} = Subscriber.start_link(self)

    all_stream = Process.whereis(EventStore.Streams.AllStream)

    {:ok, subscription1} = Subscriptions.subscribe_to_all_streams(all_stream, @subscription_name <> "1", subscriber1)
    {:ok, subscription2} = Subscriptions.subscribe_to_all_streams(all_stream, @subscription_name <> "2", subscriber2)

    # unlink subscriber so we don't crash the test when it is terminated by the subscription shutdown
    Process.unlink(subscriber1)

    ProcessHelper.shutdown(subscription1)

    # should still notify subscription 2
    {:ok, 1} = Appender.append(conn, stream_id, events)
    {:ok, persisted_events} = Reader.read_forward(conn, stream_id, 0)

    Subscriptions.notify_events(stream_uuid, persisted_events)

    # should kill subscription and subscriber
    assert Process.alive?(subscription1) == false
    assert Process.alive?(subscriber1) == false

    # other subscription should be unaffected
    assert Process.alive?(subscription2) == true
    assert Process.alive?(subscriber2) == true

    # subscription 2 should still receive events
    assert_receive {:events, received_events}, @receive_timeout
    expected_events = EventFactory.deserialize_events(persisted_events)

    assert received_events == expected_events
    assert Subscriber.received_events(subscriber2) == expected_events
  end

  test "should monitor single stream subscription, terminate subscription and subscriber on error", %{conn: conn} do
    {:ok, stream_uuid, stream_id} = create_stream(conn)

    {:ok, stream} = Streams.open_stream(stream_uuid)
    {:ok, subscriber1} = Subscriber.start_link(self)
    {:ok, subscriber2} = Subscriber.start_link(self)

    {:ok, subscription1} = Subscriptions.subscribe_to_stream(stream_uuid, stream, @subscription_name <> "1", subscriber1)
    {:ok, subscription2} = Subscriptions.subscribe_to_stream(stream_uuid, stream, @subscription_name <> "2", subscriber2)

    # unlink subscriber so we don't crash the test when it is terminated by the subscription shutdown
    Process.unlink(subscriber1)

    ProcessHelper.shutdown(subscription1)

    # should still notify subscription 2
    {:ok, persisted_events} = notify_events(conn, stream_id, stream_uuid)

    # should kill subscription and subscriber
    assert Process.alive?(subscription1) == false
    assert Process.alive?(subscriber1) == false

    # other subscription should be unaffected
    assert Process.alive?(subscription2) == true
    assert Process.alive?(subscriber2) == true

    # subscription 2 should still receive events
    assert_receive {:events, received_events}, @receive_timeout
    expected_events = EventFactory.deserialize_events(persisted_events)

    assert received_events == expected_events
    assert Subscriber.received_events(subscriber2) == expected_events
  end

  test "should unsubscribe from a single stream subscription", %{conn: conn} do
    {:ok, stream_uuid, stream_id} = create_stream(conn)
    {:ok, stream} = Streams.open_stream(stream_uuid)
    {:ok, subscription} = Subscriptions.subscribe_to_stream(stream_uuid, stream, @subscription_name, self)

    :ok = Subscriptions.unsubscribe_from_stream(stream_uuid, @subscription_name)

    {:ok, _persisted_events} = notify_events(conn, stream_id, stream_uuid)

    refute_receive {:events, _received_events}
    assert Process.alive?(subscription) == false
  end

  test "should unsubscribe from a single stream subscription when not started", %{conn: conn} do
    {:ok, stream_uuid, stream_id} = create_stream(conn)
    {:ok, stream} = Streams.open_stream(stream_uuid)
    {:ok, subscription} = Subscriptions.subscribe_to_stream(stream_uuid, stream, @subscription_name, self)

    ProcessHelper.shutdown(subscription)

    :ok = Subscriptions.unsubscribe_from_stream(stream_uuid, @subscription_name)

    {:ok, _persisted_events} = notify_events(conn, stream_id, stream_uuid)

    refute_receive {:events, _received_events}
    assert Process.alive?(subscription) == false
  end

  # test "resume subscription to stream should skip already seen events", %{conn: conn}

  defp create_stream(conn) do
    stream_uuid = UUID.uuid4
    {:ok, stream_id} = Stream.create_stream(conn, stream_uuid)
    {:ok, stream_uuid, stream_id}
  end

  defp notify_events(conn, stream_id, stream_uuid, number_of_events \\ 1) do
    {:ok, ^number_of_events} = Appender.append(conn, stream_id, EventFactory.create_recorded_events(number_of_events, stream_id))
    {:ok, persisted_events} = Reader.read_forward(conn, stream_id, 0)

    Subscriptions.notify_events(stream_uuid, persisted_events)

    {:ok, persisted_events}
  end
end
