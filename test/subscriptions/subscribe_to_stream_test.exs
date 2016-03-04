defmodule EventStore.Subscription.SubscribeToStream do
  use ExUnit.Case
  doctest EventStore.Storage

  alias EventStore.EventFactory
  alias EventStore.Storage
  alias EventStore.Subscriptions

  defmodule Subscriber do
    use GenServer

    def start_link(sender) do
      GenServer.start_link(__MODULE__, sender, [])
    end

    def received_events(server) do
      GenServer.call(server, :received_events)
    end

    def init(sender) do
      {:ok, %{sender: sender, events: []}}
    end

    def handle_info({:events, _stream_uuid, _stream_version, events} = message, state) do
      send(state.sender, message)
      {:noreply, %{state | events: events ++ state.events}}
    end

    def handle_call(:received_events, _from, state) do
      result = state.events |> Enum.reverse
      {:reply, result, state}
    end
  end

  @all_stream "$all"
  @subscription_name "test_subscription"

  setup do
    {:ok, storage} = Storage.start_link
    :ok = Storage.reset!(storage)
    {:ok, supervisor} = Subscriptions.Supervisor.start_link(storage)
    {:ok, subscriptions} = Subscriptions.start_link(supervisor)
    {:ok, storage: storage, supervisor: supervisor, subscriptions: subscriptions}
  end

  test "subscribe to stream", %{subscriptions: subscriptions} do
    stream_uuid = UUID.uuid4()
    events = EventFactory.create_events(1)

    {:ok, subscriber} = Subscriber.start_link(self)
    {:ok, _subscription} = Subscriptions.subscribe_to_stream(subscriptions, stream_uuid, @subscription_name, subscriber)

    Subscriptions.notify_events(subscriptions, stream_uuid, length(events), events)

    assert_receive {:events, received_stream_uuid, received_stream_version, received_events}

    assert received_stream_uuid == stream_uuid
    assert received_stream_version == 1
    assert received_events == events
    assert Subscriber.received_events(subscriber) == events
  end

  test "subscribe to stream, ignore events from another stream", %{subscriptions: subscriptions} do
    interested_stream_uuid = UUID.uuid4()
    other_stream_uuid = UUID.uuid4()
    events = EventFactory.create_events(1)

    {:ok, subscriber} = Subscriber.start_link(self)
    {:ok, _subscription} = Subscriptions.subscribe_to_stream(subscriptions, interested_stream_uuid, @subscription_name, subscriber)

    Subscriptions.notify_events(subscriptions, other_stream_uuid, length(events), events)

    refute_receive {:events, _received_stream_uuid, _received_stream_version, _received_events}

    assert Subscriber.received_events(subscriber) == []
  end

  test "subscribe to $all stream, receive events from all streams", %{subscriptions: subscriptions} do
    stream1_uuid = UUID.uuid4()
    stream2_uuid = UUID.uuid4()
    stream1_events = EventFactory.create_events(1)
    stream2_events = EventFactory.create_events(1)

    {:ok, subscriber} = Subscriber.start_link(self)
    {:ok, _subscription} = Subscriptions.subscribe_to_stream(subscriptions, @all_stream, @subscription_name, subscriber)

    Subscriptions.notify_events(subscriptions, stream1_uuid, length(stream1_events), stream1_events)
    Subscriptions.notify_events(subscriptions, stream2_uuid, length(stream2_events), stream2_events)

    assert_receive {:events, received_stream1_uuid, received_stream1_version, stream1_received_events}
    assert_receive {:events, received_stream2_uuid, received_stream2_version, stream2_received_events}

    assert received_stream1_uuid == stream1_uuid
    assert received_stream1_version == 1
    assert stream1_received_events == stream1_events

    assert received_stream2_uuid == stream2_uuid
    assert received_stream2_version == 1
    assert stream2_received_events == stream2_events

    assert Subscriber.received_events(subscriber) == stream1_events ++ stream2_events
  end

  test "should monitor each subscription, terminate subscriber on error", %{subscriptions: subscriptions} do
    stream_uuid = UUID.uuid4()
    events = EventFactory.create_events(1)

    {:ok, subscriber1} = Subscriber.start_link(self)
    {:ok, subscriber2} = Subscriber.start_link(self)

    {:ok, subscription1} = Subscriptions.subscribe_to_stream(subscriptions, stream_uuid, @subscription_name <> "1", subscriber1)
    {:ok, _subscription2} = Subscriptions.subscribe_to_stream(subscriptions, stream_uuid, @subscription_name <> "2", subscriber2)

    # unlink subscriber so we don't crash the test when it is terminated by the subscription shutdown
    Process.unlink(subscriber1)

    shutdown(subscription1)

    # should still notify subscription 2
    Subscriptions.notify_events(subscriptions, stream_uuid, length(events), events)

    # should kill subscription and subscriber
    assert Process.alive?(subscription1) == false
    assert Process.alive?(subscriber1) == false

    # subscription 2 should still receive events
    assert_receive {:events, received_stream_uuid, received_stream_version, received_events}

    assert received_stream_uuid == stream_uuid
    assert received_stream_version == 1
    assert received_events == events
    assert Subscriber.received_events(subscriber2) == events
  end

  # stop the process with non-normal reason
  defp shutdown(pid) do
    Process.unlink(pid)
    Process.exit(pid, :shutdown)

    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, _, _, _}
  end
end
