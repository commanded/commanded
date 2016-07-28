defmodule EventStore.Subscriptions.Subscription do
  @moduledoc """
  Subscription to a single, or all, event streams.

  A subscription is persistent so that resuming the subscription will continue from the last acknowledged event.
  This guarantees at least once delivery of every event appended to storage.
  """

  use GenServer
  require Logger

  alias EventStore.Subscriptions.{AllStreamsSubscription,SingleStreamSubscription,Subscription}

  @all_stream "$all"

  defstruct stream_uuid: nil, stream: nil, subscription_name: nil, subscriber: nil, subscription: nil

  def start_link(stream_uuid, stream, subscription_name, subscriber) do
    GenServer.start_link(__MODULE__, %Subscription{
      stream_uuid: stream_uuid,
      stream: stream,
      subscription_name: subscription_name,
      subscriber: subscriber,
      subscription: subscription_provider(stream_uuid).new
    })
  end

  def notify_events(subscription, events) do
    GenServer.cast(subscription, {:notify_events, events})
  end

  def unsubscribe(subscription) do
    GenServer.call(subscription, {:unsubscribe})
  end

  def init(%Subscription{subscriber: subscriber} = state) do
    Process.link(subscriber)

    GenServer.cast(self, {:subscribe_to_stream})

    {:ok, state}
  end

  def handle_cast({:subscribe_to_stream}, %Subscription{stream_uuid: stream_uuid, stream: stream, subscription_name: subscription_name, subscriber: subscriber, subscription: subscription} = state) do
    subscription =
      subscription
      |> subscription_provider(stream_uuid).subscribe(stream_uuid, stream, subscription_name, subscriber)

    handle_subscription_state(subscription.state)

    {:noreply, %Subscription{state | subscription: subscription}}
  end

  def handle_cast({:notify_events, events}, %Subscription{stream_uuid: stream_uuid, subscription: subscription} = state) do
    subscription =
      subscription
      |> subscription_provider(stream_uuid).notify_events(events)

    handle_subscription_state(subscription.state)

    {:noreply, %Subscription{state | subscription: subscription}}
  end

  def handle_cast({:catch_up}, %Subscription{stream_uuid: stream_uuid, subscription: subscription} = state) do
    subscription =
      subscription
      |> subscription_provider(stream_uuid).catch_up

    handle_subscription_state(subscription.state)

    {:noreply, %Subscription{state | subscription: subscription}}
  end

  def handle_call({:unsubscribe}, _from, %Subscription{stream_uuid: stream_uuid, subscriber: subscriber, subscription: subscription} = state) do
    Process.unlink(subscriber)

    subscription =
      subscription
      |> subscription_provider(stream_uuid).unsubscribe

    handle_subscription_state(subscription.state)

    {:reply, :ok, %Subscription{state | subscription: subscription}}
  end

  defp handle_subscription_state(:catching_up) do
    GenServer.cast(self, {:catch_up})
  end

  defp handle_subscription_state(_) do
    # no-op
  end

  defp subscription_provider(@all_stream) do
    AllStreamsSubscription
  end

  defp subscription_provider(_stream_uuid) do
    SingleStreamSubscription
  end
end
