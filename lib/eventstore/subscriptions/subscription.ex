defmodule EventStore.Subscriptions.Subscription do
  @moduledoc """
  Subscription to a single, or all event streams.

  A subscription is persistent so that resuming the subscription will continue from the last acknowledged event.
  This guarantees at least once delivery of every event from the store.
  """

  use GenServer
  require Logger

  alias EventStore.Subscriptions.{PersistentSubscription,Subscription}

  defstruct storage: nil, stream_uuid: nil, subscription_name: nil, subscriber: nil, subscription: nil

  def start_link(storage, stream_uuid, subscription_name, subscriber) do
    GenServer.start_link(__MODULE__, %Subscription{
      storage: storage,
      stream_uuid: stream_uuid,
      subscription_name: subscription_name,
      subscriber: subscriber,
      subscription: PersistentSubscription.new
    })
  end

  def notify_events(subscription, events) do
    GenServer.cast(subscription, {:notify_events, events})
  end

  def init(%Subscription{storage: storage, stream_uuid: stream_uuid, subscription_name: subscription_name, subscriber: subscriber, subscription: subscription} = state) do
    Process.link(subscriber)

    subscription =
      subscription
      |> PersistentSubscription.subscribe(storage, stream_uuid, subscription_name, subscriber)
      |> PersistentSubscription.catch_up

    state = %Subscription{state | subscription: subscription}
    {:ok, state}
  end

  def handle_cast({:notify_events, events}, %Subscription{subscription: subscription} = state) do
    subscription =
      subscription
      |> PersistentSubscription.notify_events(events)

    state = %Subscription{state | subscription: subscription}
    {:noreply, state}
  end
end
