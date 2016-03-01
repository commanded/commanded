defmodule EventStore.Subscriptions.Subscription do
  use GenServer
  require Logger

  alias EventStore.Storage
  alias EventStore.Subscriptions.Subscription

  defstruct storage: nil, stream_uuid: nil, subscription_name: nil, subscriber: nil

  def start_link(storage, stream_uuid, subscription_name, subscriber) do
    GenServer.start_link(__MODULE__, %Subscription{
      storage: storage,
      stream_uuid: stream_uuid,
      subscription_name: subscription_name,
      subscriber: subscriber
    })
  end

  def notify_events(subscription, stream_uuid, stream_version, events) do
    GenServer.cast(subscription, {:notify_events, stream_uuid, stream_version, events})
  end

  def init(%Subscription{subscriber: subscriber} = subscription) do
    Process.link(subscriber)
    {:ok, subscription}
  end

  def handle_cast({:notify_events, stream_uuid, stream_version, events}, %Subscription{} = state) do
    send(state.subscriber, {:events, stream_uuid, stream_version, events})
    {:noreply, state}
  end
end
