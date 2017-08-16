defmodule EventStore.Subscriptions.SubscribeToStream do
  use EventStore.StorageCase

  alias EventStore.{EventFactory,ProcessHelper}
  alias EventStore.{Streams,Subscriptions,Subscriber}
  alias EventStore.Subscriptions.Subscription
  alias EventStore.Streams.Stream

  setup do
    subscription_name = UUID.uuid4()

    {:ok, %{subscription_name: subscription_name}}
  end

  describe "single stream subscription" do
    test "subscribe to single stream from origin should receive all its events", %{subscription_name: subscription_name} do
      stream_uuid = UUID.uuid4
      events = EventFactory.create_events(1)

      {:ok, _stream} = Streams.Supervisor.open_stream(stream_uuid)

      {:ok, _subscription} = Subscriptions.subscribe_to_stream(stream_uuid, subscription_name, self())

      :ok = Stream.append_to_stream(stream_uuid, 0, events)

      assert_receive {:events, received_events}
      assert pluck(received_events, :data) == pluck(events, :data)
    end

    test "subscribe to single stream from given stream version should only receive later events", %{subscription_name: subscription_name} do
      stream_uuid = UUID.uuid4
      initial_events = EventFactory.create_events(1)
      new_events = EventFactory.create_events(1, 2)

      {:ok, _stream} = Streams.Supervisor.open_stream(stream_uuid)
      :ok = Stream.append_to_stream(stream_uuid, 0, initial_events)

      {:ok, _subscription} = Subscriptions.subscribe_to_stream(stream_uuid, subscription_name, self(), start_from_stream_version: 1)

      :ok = Stream.append_to_stream(stream_uuid, 1, new_events)

      assert_receive {:events, received_events}
      assert pluck(received_events, :data) == pluck(new_events, :data)
    end

    test "subscribe to stream more than once using same subscription name should error", %{subscription_name: subscription_name} do
      stream_uuid = UUID.uuid4
      {:ok, _stream} = Streams.Supervisor.open_stream(stream_uuid)

      {:ok, _subscription} = Subscriptions.subscribe_to_stream(stream_uuid, subscription_name, self())
      {:error, :subscription_already_exists} = Subscriptions.subscribe_to_stream(stream_uuid, subscription_name, self())
    end

    test "subscribe to single stream should ignore events from another stream", %{subscription_name: subscription_name} do
      interested_stream_uuid = UUID.uuid4
      other_stream_uuid = UUID.uuid4

      interested_events = EventFactory.create_events(1)
      other_events = EventFactory.create_events(1)

      {:ok, _interested_stream} = Streams.Supervisor.open_stream(interested_stream_uuid)
      {:ok, _other_stream} = Streams.Supervisor.open_stream(other_stream_uuid)

      {:ok, _subscription} = Subscriptions.subscribe_to_stream(interested_stream_uuid, subscription_name, self())

      :ok = Stream.append_to_stream(interested_stream_uuid, 0, interested_events)
      :ok = Stream.append_to_stream(other_stream_uuid, 0, other_events)

      # received events should not include events from the other stream
      assert_receive {:events, received_events}
      assert pluck(received_events, :data) == pluck(interested_events, :data)
    end

    test "subscribe to single stream with mapper function should receive all its mapped events", %{subscription_name: subscription_name} do
      stream_uuid = UUID.uuid4
      events = EventFactory.create_events(3)

      {:ok, _stream} = Streams.Supervisor.open_stream(stream_uuid)

      {:ok, _subscription} = Subscriptions.subscribe_to_stream(stream_uuid, subscription_name, self(), mapper: fn event -> event.event_id end)

      :ok = Stream.append_to_stream(stream_uuid, 0, events)

      assert_receive {:events, received_mapped_events}
      assert received_mapped_events == [1, 2, 3]
    end
  end

  describe "all stream subscription" do
    test "subscribe to all streams should receive events from all streams", %{subscription_name: subscription_name} do
      stream1_uuid = UUID.uuid4
      stream2_uuid = UUID.uuid4

      stream1_events = EventFactory.create_events(1)
      stream2_events = EventFactory.create_events(1)

      {:ok, subscription} = Subscriptions.subscribe_to_all_streams(subscription_name, self())

      {:ok, _stream1} = Streams.Supervisor.open_stream(stream1_uuid)
      {:ok, _stream2} = Streams.Supervisor.open_stream(stream2_uuid)

      :ok = Stream.append_to_stream(stream1_uuid, 0, stream1_events)
      :ok = Stream.append_to_stream(stream2_uuid, 0, stream2_events)

      assert_receive {:events, stream1_received_events}
      Subscription.ack(subscription, stream1_received_events)

      assert_receive {:events, stream2_received_events}

      assert pluck(stream1_received_events, :data) == pluck(stream1_events, :data)
      assert pluck(stream2_received_events, :data) == pluck(stream2_events, :data)
      assert stream1_received_events != stream2_received_events
    end

    test "subscribe to all streams from given stream id should only receive later events from all streams", %{subscription_name: subscription_name} do
      stream1_uuid = UUID.uuid4
      stream2_uuid = UUID.uuid4

      stream1_initial_events = EventFactory.create_events(1)
      stream2_initial_events = EventFactory.create_events(1)
      stream1_new_events = EventFactory.create_events(1, 2)
      stream2_new_events = EventFactory.create_events(1, 2)

      {:ok, _stream1} = Streams.Supervisor.open_stream(stream1_uuid)
      {:ok, _stream2} = Streams.Supervisor.open_stream(stream2_uuid)

      :ok = Stream.append_to_stream(stream1_uuid, 0, stream1_initial_events)
      :ok = Stream.append_to_stream(stream2_uuid, 0, stream2_initial_events)

      {:ok, subscription} = Subscriptions.subscribe_to_all_streams(subscription_name, self(), start_from_event_id: 2)

      :ok = Stream.append_to_stream(stream1_uuid, 1, stream1_new_events)
      :ok = Stream.append_to_stream(stream2_uuid, 1, stream2_new_events)

      assert_receive {:events, stream1_received_events}
      Subscription.ack(subscription, stream1_received_events)

      assert_receive {:events, stream2_received_events}

      assert pluck(stream1_received_events, :data) == pluck(stream1_new_events, :data)
      assert pluck(stream2_received_events, :data) == pluck(stream2_new_events, :data)
      assert stream1_received_events != stream2_received_events
    end

    test "should monitor all stream subscription, terminate subscription and subscriber on error", %{subscription_name: subscription_name} do
      stream_uuid = UUID.uuid4
      events = EventFactory.create_events(1)

      {:ok, _stream} = Streams.Supervisor.open_stream(stream_uuid)

      {:ok, subscriber1} = Subscriber.start(self())
      {:ok, subscriber2} = Subscriber.start_link(self())

      {:ok, subscription1} = Subscriptions.subscribe_to_all_streams(subscription_name <> "1", subscriber1)
      {:ok, subscription2} = Subscriptions.subscribe_to_all_streams(subscription_name <> "2", subscriber2)

      ProcessHelper.shutdown(subscription1)

      # should kill subscription and subscriber
      assert Process.alive?(subscription1) == false
      assert Process.alive?(subscriber1) == false

      # other subscription should be unaffected
      assert Process.alive?(subscription2) == true
      assert Process.alive?(subscriber2) == true

      # wait for subscriptions to receive DOWN notification
      :timer.sleep(500)

      # appending events to stream should notify subscription 2
      :ok = Stream.append_to_stream(stream_uuid, 0, events)

      # subscription 2 should still receive events
      assert_receive {:events, received_events}
      refute_receive {:events, _events}

      assert pluck(received_events, :data) == pluck(events, :data)
      assert pluck(Subscriber.received_events(subscriber2), :data) == pluck(events, :data)
    end

    test "should ack received events", %{subscription_name: subscription_name} do
      stream_uuid = UUID.uuid4
      stream_events = EventFactory.create_events(6)
      initial_events = Enum.take(stream_events, 3)
      remaining_events = Enum.drop(stream_events, 3)

      {:ok, subscription} = Subscriptions.subscribe_to_all_streams(subscription_name, self())

      {:ok, _stream} = Streams.Supervisor.open_stream(stream_uuid)

      :ok = Stream.append_to_stream(stream_uuid, 0, initial_events)

      assert_receive {:events, initial_received_events}
      assert length(initial_received_events) == 3
      assert pluck(initial_received_events, :data) == pluck(initial_events, :data)

      # acknowledge receipt of first event only
      Subscription.ack(subscription, hd(initial_received_events))

      refute_receive {:events, _events}

      # should not send further events until ack'd all previous
      :ok = Stream.append_to_stream(stream_uuid, 3, remaining_events)

      refute_receive {:events, _events}

      # acknowledge receipt of all initial events
      Subscription.ack(subscription, initial_received_events)

      assert_receive {:events, remaining_received_events}
      assert length(remaining_received_events) == 3
      assert pluck(remaining_received_events, :data) == pluck(remaining_events, :data)
    end
  end

  describe "monitor single stream subscription" do
    test "should monitor subscription and terminate subscription and subscriber on error", %{subscription_name: subscription_name} do
      stream_uuid = UUID.uuid4
      events = EventFactory.create_events(1)

      {:ok, _stream} = Streams.Supervisor.open_stream(stream_uuid)
      {:ok, subscriber1} = Subscriber.start_link(self())
      {:ok, subscriber2} = Subscriber.start_link(self())

      {:ok, subscription1} = Subscriptions.subscribe_to_stream(stream_uuid, subscription_name <> "-1", subscriber1)
      {:ok, subscription2} = Subscriptions.subscribe_to_stream(stream_uuid, subscription_name <> "-2", subscriber2)

      refute_receive {:events, _events}

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
      :ok = Stream.append_to_stream(stream_uuid, 0, events)

      # subscription 2 should still receive events
      assert_receive {:events, received_events}
      refute_receive {:events, _events}

      assert pluck(received_events, :data) == pluck(events, :data)
      assert pluck(Subscriber.received_events(subscriber2), :data) == pluck(events, :data)
    end

    test "should monitor subscriber and terminate subscription on error", %{subscription_name: subscription_name} do
      stream_uuid = UUID.uuid4
      events = EventFactory.create_events(1)

      {:ok, _stream} = Streams.Supervisor.open_stream(stream_uuid)
      {:ok, subscriber1} = Subscriber.start_link(self())
      {:ok, subscriber2} = Subscriber.start_link(self())

      {:ok, subscription1} = Subscriptions.subscribe_to_stream(stream_uuid, subscription_name <> "-1", subscriber1)
      {:ok, subscription2} = Subscriptions.subscribe_to_stream(stream_uuid, subscription_name <> "-2", subscriber2)

      refute_receive {:events, _events}

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
      :ok = Stream.append_to_stream(stream_uuid, 0, events)

      # subscription 2 should still receive events
      assert_receive {:events, received_events}
      refute_receive {:events, _events}

      assert pluck(received_events, :data) == pluck(events, :data)
      assert pluck(Subscriber.received_events(subscriber2), :data) == pluck(events, :data)
    end

    test "unsubscribe from a single stream subscription should stop subscriber from receiving events", %{subscription_name: subscription_name} do
      stream_uuid = UUID.uuid4
      events = EventFactory.create_events(1)

      {:ok, _stream} = Streams.Supervisor.open_stream(stream_uuid)
      {:ok, subscription} = Subscriptions.subscribe_to_stream(stream_uuid, subscription_name, self())

      :ok = Subscriptions.unsubscribe_from_stream(stream_uuid, subscription_name)

      :ok = Stream.append_to_stream(stream_uuid, 0, events)

      refute_receive {:events, _received_events}
      assert Process.alive?(subscription) == false
    end
  end

  defmodule CollectingSubscriber do
    use GenServer

    def start_link(subscription_name) do
      GenServer.start_link(__MODULE__, subscription_name)
    end

    def received_events(subscriber) do
      GenServer.call(subscriber, {:received_events})
    end

    def init(subscription_name) do
      {:ok, subscription} = Subscriptions.subscribe_to_all_streams(subscription_name, self())

      {:ok, %{events: [], subscription: subscription}}
    end

    def handle_call({:received_events}, _from, %{events: events} = state) do
      {:reply, events, state}
    end

    def handle_info({:events, received_events}, %{events: events, subscription: subscription} = state) do
      Subscription.ack(subscription, received_events)

      {:noreply, %{state | events: events ++ received_events}}
    end
  end

  describe "many subscriptions to all stream" do
    test "should all receive events from any stream", %{subscription_name: subscription_name} do
      stream1_uuid = UUID.uuid4()
      stream2_uuid = UUID.uuid4()

      stream1_events = EventFactory.create_events(3)
      stream2_events = EventFactory.create_events(3)

      {:ok, subscriber1} = CollectingSubscriber.start_link(subscription_name <> "-1")
      {:ok, subscriber2} = CollectingSubscriber.start_link(subscription_name <> "-2")
      {:ok, subscriber3} = CollectingSubscriber.start_link(subscription_name <> "-3")
      {:ok, subscriber4} = CollectingSubscriber.start_link(subscription_name <> "-4")

      {:ok, _stream1} = Streams.Supervisor.open_stream(stream1_uuid)
      {:ok, _stream2} = Streams.Supervisor.open_stream(stream2_uuid)

      :ok = Stream.append_to_stream(stream1_uuid, 0, stream1_events)
      :ok = Stream.append_to_stream(stream2_uuid, 0, stream2_events)

      :timer.sleep 2_000

      all_received_events =
        [subscriber1, subscriber2, subscriber3, subscriber4]
        |> Enum.reduce([], fn (subscriber, events) ->
          events ++ CollectingSubscriber.received_events(subscriber)
        end)

      assert length(all_received_events) == 4 * 6
    end
  end

  defp pluck(enumerable, field) do
    Enum.map(enumerable, &Map.get(&1, field))
  end
end
