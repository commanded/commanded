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

  def init(%Subscription{} = subscription) do
    {:ok, subscription}
  end
end
