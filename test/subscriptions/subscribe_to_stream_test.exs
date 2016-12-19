defmodule EventStore.Subscriptions.SubscribeToStream do
  use EventStore.StorageCase
  doctest EventStore.Subscriptions.Supervisor
  doctest EventStore.Subscriptions.Subscription

  alias EventStore.{EventFactory,ProcessHelper}
  alias EventStore.{Streams,Subscriptions,Subscriber}
  alias EventStore.Streams.Stream

  @receive_timeout 1_000

  setup do
    subscription_name = UUID.uuid4
    all_stream = Process.whereis(EventStore.Streams.AllStream)

    {:ok, %{subscription_name: subscription_name, all_stream: all_stream}}
  end

  test "subscribe to single stream", %{subscription_name: subscription_name} do
    stream_uuid = UUID.uuid4
    events = EventFactory.create_events(1)

    {:ok, stream} = Streams.open_stream(stream_uuid)

    {:ok, subscription} = Subscriptions.subscribe_to_stream(stream_uuid, stream, subscription_name, self)

    :ok = Stream.append_to_stream(stream, 0, events)

    assert_receive {:events, received_events, ^subscription}, @receive_timeout
    assert pluck(received_events, :data) == pluck(events, :data)
  end

  test "subscribe to stream more than once using same subscription name should error", %{subscription_name: subscription_name} do
    stream_uuid = UUID.uuid4
    {:ok, stream} = Streams.open_stream(stream_uuid)

    {:ok, _} = Subscriptions.subscribe_to_stream(stream_uuid, stream, subscription_name, self)
    {:error, :subscription_already_exists} = Subscriptions.subscribe_to_stream(stream_uuid, stream, subscription_name, self)
  end

  test "subscribe to single stream should ignore events from another stream", %{subscription_name: subscription_name} do
    interested_stream_uuid = UUID.uuid4
    other_stream_uuid = UUID.uuid4

    interested_events = EventFactory.create_events(1)
    other_events = EventFactory.create_events(1)

    {:ok, interested_stream} = Streams.open_stream(interested_stream_uuid)
    {:ok, other_stream} = Streams.open_stream(other_stream_uuid)

    {:ok, subscription} = Subscriptions.subscribe_to_stream(interested_stream_uuid, interested_stream, subscription_name, self)

    :ok = Stream.append_to_stream(interested_stream, 0, interested_events)
    :ok = Stream.append_to_stream(other_stream, 0, other_events)

    # received events should not include events from the other stream
    assert_receive {:events, received_events, ^subscription}, @receive_timeout
    assert pluck(received_events, :data) == pluck(interested_events, :data)
  end

  describe "all stream subscription" do
    test "subscribe to all streams should receive events from all streams", %{subscription_name: subscription_name, all_stream: all_stream} do
      stream1_uuid = UUID.uuid4
      stream2_uuid = UUID.uuid4

      stream1_events = EventFactory.create_events(1)
      stream2_events = EventFactory.create_events(1)

      {:ok, subscription} = Subscriptions.subscribe_to_all_streams(all_stream, subscription_name, self)

      {:ok, stream1} = Streams.open_stream(stream1_uuid)
      {:ok, stream2} = Streams.open_stream(stream2_uuid)

      :ok = Stream.append_to_stream(stream1, 0, stream1_events)
      :ok = Stream.append_to_stream(stream2, 0, stream2_events)

      assert_receive {:events, stream1_received_events, ^subscription}, @receive_timeout
      send(subscription, {:ack, List.last(stream1_received_events).event_id})

      assert_receive {:events, stream2_received_events, ^subscription}, @receive_timeout

      assert pluck(stream1_received_events, :data) == pluck(stream1_events, :data)
      assert pluck(stream2_received_events, :data) == pluck(stream2_events, :data)
      assert stream1_received_events != stream2_received_events
    end

    test "should monitor all stream subscription, terminate subscription and subscriber on error", %{subscription_name: subscription_name, all_stream: all_stream} do
      stream_uuid = UUID.uuid4
      events = EventFactory.create_events(1)

      {:ok, stream} = Streams.open_stream(stream_uuid)

      {:ok, subscriber1} = Subscriber.start_link(self)
      {:ok, subscriber2} = Subscriber.start_link(self)

      {:ok, subscription1} = Subscriptions.subscribe_to_all_streams(all_stream, subscription_name <> "1", subscriber1)
      {:ok, subscription2} = Subscriptions.subscribe_to_all_streams(all_stream, subscription_name <> "2", subscriber2)

      # unlink subscriber so we don't crash the test when it is terminated by the subscription shutdown
      Process.unlink(subscriber1)

      ProcessHelper.shutdown(subscription1)

      # should kill subscription and subscriber
      assert Process.alive?(subscription1) == false
      assert Process.alive?(subscriber1) == false

      # other subscription should be unaffected
      assert Process.alive?(subscription2) == true
      assert Process.alive?(subscriber2) == true

      # appending events to stream should notify subscription 2
      :ok = Stream.append_to_stream(stream, 0, events)

      # subscription 2 should still receive events
      assert_receive {:events, received_events}, @receive_timeout
      refute_receive {:events, _events}, @receive_timeout

      assert pluck(received_events, :data) == pluck(events, :data)
      assert pluck(Subscriber.received_events(subscriber2), :data) == pluck(events, :data)
    end

    test "should ack received events", %{subscription_name: subscription_name, all_stream: all_stream} do
      stream_uuid = UUID.uuid4
      stream_events = EventFactory.create_events(6)
      initial_events = Enum.take(stream_events, 3)
      remaining_events = Enum.drop(stream_events, 3)

      {:ok, subscription} = Subscriptions.subscribe_to_all_streams(all_stream, subscription_name, self)

      {:ok, stream} = Streams.open_stream(stream_uuid)

      :ok = Stream.append_to_stream(stream, 0, initial_events)

      assert_receive {:events, initial_received_events, ^subscription}, @receive_timeout
      assert length(initial_received_events) == 3
      assert pluck(initial_received_events, :data) == pluck(initial_events, :data)

      # acknowledge receipt of first event only
      send(subscription, {:ack, 1})

      refute_receive {:events, _events, ^subscription}, @receive_timeout

      # should not send further events until ack'd all previous
      :ok = Stream.append_to_stream(stream, 3, remaining_events)

      refute_receive {:events, _events, ^subscription}, @receive_timeout

      # acknowledge receipt of all initial events
      send(subscription, {:ack, 3})

      assert_receive {:events, remaining_received_events, ^subscription}, @receive_timeout
      assert length(remaining_received_events) == 3
      assert pluck(remaining_received_events, :data) == pluck(remaining_events, :data)
    end

    # test "resume subscription to stream should skip already seen events", %{subscription_name: subscription_name}
  end

  describe "single stream subscription" do
    test "should monitor subscription and terminate subscription and subscriber on error", %{subscription_name: subscription_name} do
      stream_uuid = UUID.uuid4
      events = EventFactory.create_events(1)

      {:ok, stream} = Streams.open_stream(stream_uuid)
      {:ok, subscriber1} = Subscriber.start_link(self)
      {:ok, subscriber2} = Subscriber.start_link(self)

      {:ok, subscription1} = Subscriptions.subscribe_to_stream(stream_uuid, stream, subscription_name <> "-1", subscriber1)
      {:ok, subscription2} = Subscriptions.subscribe_to_stream(stream_uuid, stream, subscription_name <> "-2", subscriber2)

      send(subscription1, {:ack, 1})
      send(subscription2, {:ack, 1})

      # unlink subscriber so we don't crash the test when it is terminated by the subscription shutdown
      Process.unlink(subscriber1)

      ProcessHelper.shutdown(subscription1)

      # should kill subscription and subscriber
      assert Process.alive?(subscription1) == false
      assert Process.alive?(subscriber1) == false

      # other subscription should be unaffected
      assert Process.alive?(subscription2) == true
      assert Process.alive?(subscriber2) == true

      # should still notify subscription 2
      :ok = Stream.append_to_stream(stream, 0, events)

      # subscription 2 should still receive events
      assert_receive {:events, received_events}, @receive_timeout
      refute_receive {:events, _events}, @receive_timeout

      assert pluck(received_events, :data) == pluck(events, :data)
      assert pluck(Subscriber.received_events(subscriber2), :data) == pluck(events, :data)
    end

    test "should monitor subscriber and terminate subscription on error", %{subscription_name: subscription_name} do
      stream_uuid = UUID.uuid4
      events = EventFactory.create_events(1)

      {:ok, stream} = Streams.open_stream(stream_uuid)
      {:ok, subscriber1} = Subscriber.start_link(self)
      {:ok, subscriber2} = Subscriber.start_link(self)

      {:ok, subscription1} = Subscriptions.subscribe_to_stream(stream_uuid, stream, subscription_name <> "-1", subscriber1)
      {:ok, subscription2} = Subscriptions.subscribe_to_stream(stream_uuid, stream, subscription_name <> "-2", subscriber2)

      send(subscription1, {:ack, 1})
      send(subscription2, {:ack, 1})

      # unlink subscriber so we don't crash the test when it is terminated by the subscription shutdown
      Process.unlink(subscriber1)

      ProcessHelper.shutdown(subscriber1)

      # should kill subscription and subscriber
      assert Process.alive?(subscription1) == false
      assert Process.alive?(subscriber1) == false

      # other subscription should be unaffected
      assert Process.alive?(subscription2) == true
      assert Process.alive?(subscriber2) == true

      # should still notify subscription 2
      :ok = Stream.append_to_stream(stream, 0, events)

      # subscription 2 should still receive events
      assert_receive {:events, received_events}, @receive_timeout
      refute_receive {:events, _events}, @receive_timeout

      assert pluck(received_events, :data) == pluck(events, :data)
      assert pluck(Subscriber.received_events(subscriber2), :data) == pluck(events, :data)
    end

    test "unsubscribe from a single stream subscription should stop subscriber from receiving events", %{subscription_name: subscription_name} do
      stream_uuid = UUID.uuid4
      events = EventFactory.create_events(1)

      {:ok, stream} = Streams.open_stream(stream_uuid)
      {:ok, subscription} = Subscriptions.subscribe_to_stream(stream_uuid, stream, subscription_name, self)

      :ok = Subscriptions.unsubscribe_from_stream(stream_uuid, subscription_name)

      :ok = Stream.append_to_stream(stream, 0, events)

      refute_receive {:events, _received_events, _subscription}
      assert Process.alive?(subscription) == false
    end

    test "unsubscribe from a single stream subscription after subscription process is shutdown should stop subscriber from receiving events", %{subscription_name: subscription_name} do
      stream_uuid = UUID.uuid4
      events = EventFactory.create_events(1)

      {:ok, stream} = Streams.open_stream(stream_uuid)
      {:ok, subscription} = Subscriptions.subscribe_to_stream(stream_uuid, stream, subscription_name, self)

      ProcessHelper.shutdown(subscription)

      :ok = Subscriptions.unsubscribe_from_stream(stream_uuid, subscription_name)

      :ok = Stream.append_to_stream(stream, 0, events)

      refute_receive {:events, _received_events, _subscription}
      assert Process.alive?(subscription) == false
    end
  end

  defp pluck(enumerable, field) do
    Enum.map(enumerable, &Map.get(&1, field))
  end
end
