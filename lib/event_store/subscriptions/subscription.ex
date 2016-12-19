defmodule EventStore.Subscriptions.Subscription do
  @moduledoc """
  Subscription to a single, or all, event streams.

  A subscription is persistent so that resuming the subscription will continue from the last acknowledged event.
  This guarantees at least once delivery of every event appended to storage.
  """

  use GenServer
  require Logger

  alias EventStore.Subscriptions.{StreamSubscription,Subscription}

  defstruct [
    stream_uuid: nil,
    stream: nil,
    subscription_name: nil,
    subscriber: nil,
    subscription: nil,
    subscription_opts: [],
  ]

  def start_link(stream_uuid, stream, subscription_name, subscriber, opts) do
    GenServer.start_link(__MODULE__, %Subscription{
      stream_uuid: stream_uuid,
      stream: stream,
      subscription_name: subscription_name,
      subscriber: subscriber,
      subscription: StreamSubscription.new,
      subscription_opts: opts,
    })
  end

  def notify_events(subscription, events) when is_list(events) do
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

  def handle_cast({:subscribe_to_stream}, %Subscription{stream_uuid: stream_uuid, stream: stream, subscription_name: subscription_name, subscriber: subscriber, subscription: subscription, subscription_opts: opts} = state) do
    subscription =
      subscription
      |> StreamSubscription.subscribe(stream_uuid, stream, subscription_name, self, subscriber, opts)

    state = %Subscription{state | subscription: subscription}

    handle_subscription_state(state)

    {:noreply, state}
  end

  def handle_cast({:notify_events, events}, %Subscription{subscription: subscription} = state) do
    subscription =
      subscription
      |> StreamSubscription.notify_events(events)

    state = %Subscription{state | subscription: subscription}

    handle_subscription_state(state)

    {:noreply, state}
  end

  def handle_cast({:catch_up}, %Subscription{subscription: subscription} = state) do
    subscription =
      subscription
      |> StreamSubscription.catch_up

    state = %Subscription{state | subscription: subscription}

    handle_subscription_state(state)

    {:noreply, state}
  end

  @doc """
  Confirm receipt of an event by id
  """
  def handle_info({:ack, last_seen_event_id}, %Subscription{subscription: subscription} = state) do
    subscription =
      subscription
      |> StreamSubscription.ack(last_seen_event_id)

    state = %Subscription{state | subscription: subscription}

    handle_subscription_state(state)

    {:noreply, state}
  end

  def handle_call({:unsubscribe}, _from, %Subscription{subscriber: subscriber, subscription: subscription} = state) do
    Process.unlink(subscriber)

    subscription =
      subscription
      |> StreamSubscription.unsubscribe

    state = %Subscription{state | subscription: subscription}

    handle_subscription_state(state)

    {:reply, :ok, state}
  end

  defp handle_subscription_state(%Subscription{subscription: %{state: :catching_up}}) do
    GenServer.cast(self, {:catch_up})
  end

  defp handle_subscription_state(%Subscription{subscription: %{state: :max_capacity}, subscription_name: subscription_name}) do
    _ = Logger.warn(fn -> "Subscription #{subscription_name} has reached max capacity, events will be ignored until it has caught up" end)
  end

  defp handle_subscription_state(_state) do
    # no-op
  end
end
