defmodule EventStore.Subscriptions do
  @moduledoc """
  Pub/sub for subscribers interested in events appended to either a single stream or all streams
  """

  require Logger

  alias EventStore.{RecordedEvent,Subscriptions}
  alias EventStore.Subscriptions.Subscription

  @all_stream "$all"

  def subscribe_to_stream(stream_uuid, subscription_name, subscriber, opts \\ [])
  def subscribe_to_stream(stream_uuid, subscription_name, subscriber, opts) do
    do_subscribe_to_stream(stream_uuid, subscription_name, subscriber, opts)
  end

  def subscribe_to_all_streams(subscription_name, subscriber, opts \\ [])
  def subscribe_to_all_streams(subscription_name, subscriber, opts) do
    do_subscribe_to_stream(@all_stream, subscription_name, subscriber, opts)
  end

  def unsubscribe_from_stream(stream_uuid, subscription_name) do
    do_unsubscribe_from_stream(stream_uuid, subscription_name)
  end

  def unsubscribe_from_all_streams(subscription_name) do
    do_unsubscribe_from_stream(@all_stream, subscription_name)
  end

  def notify_events(stream_uuid, events) do
    events = Enum.map(events, &RecordedEvent.deserialize/1)

    Enum.each([
      Task.async(fn -> notify_subscribers(stream_uuid, events) end),
      Task.async(fn -> notify_subscribers(@all_stream, events) end),
    ], &Task.await(&1))
  end

  defp do_subscribe_to_stream(stream_uuid, subscription_name, subscriber, opts) do
    _ = Logger.debug(fn -> "creating subscription process on stream #{inspect stream_uuid} named: #{inspect subscription_name}" end)

    case EventStore.Subscriptions.Supervisor.subscribe_to_stream(stream_uuid, subscription_name, subscriber, opts) do
      {:ok, subscription} -> {:ok, subscription}
      {:error, {:already_started, _subscription}} -> {:error, :subscription_already_exists}
    end
  end

  defp do_unsubscribe_from_stream(stream_uuid, subscription_name) do
    case get_subscription(stream_uuid, subscription_name) do
      nil -> :ok
      subscription ->
        :ok = Subscription.unsubscribe(subscription)
        :ok = Subscriptions.Supervisor.unsubscribe_from_stream(subscription)
    end
  end

  defp get_subscription(stream_uuid, subscription_name) do
    case Registry.lookup(EventStore.Subscriptions, {stream_uuid, subscription_name}) do
      [] -> nil
      [{subscription, _}] -> subscription
    end
  end

  defp notify_subscribers(stream_uuid, events) do
    Registry.dispatch(EventStore.Subscriptions.PubSub, stream_uuid, fn subscribers ->
      for {subscription, {module, function}} <- subscribers, do: apply(module, function, [subscription, events])
    end)
  end
end
