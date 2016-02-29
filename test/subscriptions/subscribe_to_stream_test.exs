defmodule EventStore.Subscription.SubscribeToStream do
  use ExUnit.Case
  doctest EventStore.Storage

  alias EventStore.EventFactory
  alias EventStore.Storage
  alias EventStore.Subscriptions

  defmodule Subscriber do
    use GenServer

    def start_link(sender) do
      GenServer.start_link(__MODULE__, sender, name: __MODULE__)
    end

    def received_events(server) do
      GenServer.call(server, :received_events)
    end

    def init(sender) do
      {:ok, %{sender: sender, events: []}}
    end

    def handle_info({:events, stream_uuid, stream_version, events} = message, state) do
      send(state.sender, message)
      {:noreply, %{state | events: events ++ state.events}}
    end

    def handle_call(:received_events, _from, state) do
      result = state.events |> Enum.reverse
      {:reply, result, state}
    end
  end

  @subscription_name "unit_test_subscription"

  setup do
    {:ok, storage} = Storage.start_link
    {:ok, supervisor} = Subscriptions.Supervisor.start_link(storage)
    {:ok, subscriptions} = Subscriptions.start_link(supervisor)
    {:ok, storage: storage, supervisor: supervisor, subscriptions: subscriptions}
  end

  @tag :wip
  test "subscribe to stream", %{storage: storage, subscriptions: subscriptions} do
    stream_uuid = UUID.uuid4()
    events = EventFactory.create_events(1)

    {:ok, subscriber} = Subscriber.start_link(self)
    {:ok, subscription} = Subscriptions.subscribe_to_stream(subscriptions, stream_uuid, @subscription_name, subscriber)

    Subscriptions.notify_events(subscriptions, stream_uuid, length(events), events)
    
    assert_receive {:events, received_stream_uuid, received_stream_version, received_events}

    assert received_stream_uuid == stream_uuid
    assert received_stream_version == 1
    assert received_events == events
    assert Subscriber.received_events(subscriber) == events
  end
end
