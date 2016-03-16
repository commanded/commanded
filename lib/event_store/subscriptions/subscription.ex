defmodule EventStore.Subscriptions.Subscription do
  @moduledoc """
  Subscription to a single, or all event streams.

  A subscription is persistent so that resuming the subscription will continue from the last acknowledged event.
  This guarantees at least once delivery of every event from the store.
  """

  use GenServer
  require Logger

  alias EventStore.Subscriptions.{PersistentSubscription,Subscription}

  defstruct stream_uuid: nil, subscription_name: nil, subscriber: nil, subscription: nil

  def start_link(stream_uuid, subscription_name, subscriber) do
    GenServer.start_link(__MODULE__, %Subscription{
      stream_uuid: stream_uuid,
      subscription_name: subscription_name,
      subscriber: subscriber,
      subscription: PersistentSubscription.new
    })
  end

  def notify_events(subscription, events) do
    GenServer.cast(subscription, {:notify_events, events})
  end

  def init(%Subscription{subscriber: subscriber} = state) do
    Process.link(subscriber)

    GenServer.cast(self, {:subscribe})

    {:ok, state}
  end

  def handle_cast({:subscribe}, %Subscription{stream_uuid: stream_uuid, subscription_name: subscription_name, subscriber: subscriber, subscription: subscription} = state) do
    subscription =
      subscription
      |> PersistentSubscription.subscribe(stream_uuid, subscription_name, subscriber)
      |> PersistentSubscription.catch_up

    {:noreply, %Subscription{state | subscription: subscription}}
  end

  def handle_cast({:notify_events, events}, %Subscription{subscription: subscription} = state) do
    subscription =
      subscription
      |> PersistentSubscription.notify_events(events)

    {:noreply, %Subscription{state | subscription: subscription}}
  end
end
