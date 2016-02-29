defmodule EventStore.Subscription.SubscriptionTest do
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

    def handle_info({:event, event} = message, state) do
      send(state.sender, message)
      {:noreply, %{state|events: [event|state.events]}}
    end

    def handle_call(:received_events, _from, state) do
      result = state.events |> Enum.reverse
      {:reply, result, state}
    end
  end

  @subscription_name "unit_test_subscription"

  setup do
    {:ok, store} = Storage.start_link
    {:ok, subscriptions} = Subscriptions.Supervisor.start_link(store)
    {:ok, store: store, subscriptions: subscriptions}
  end

  @tag :wip
  test "subscribe to stream", %{store: store, subscriptions: subscriptions} do
    stream_uuid = UUID.uuid4()
    events = EventFactory.create_events(1)

    {:ok, subscriber} = Subscriber.start_link(self)
    {:ok, subscription} = Subscriptions.Supervisor.subscribe_to_stream(subscriptions, stream_uuid, @subscription_name, subscriber)

    {:ok, _} = EventStore.append_to_stream(store, stream_uuid, 0, events)
  end
end
