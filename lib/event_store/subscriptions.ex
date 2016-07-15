defmodule EventStore.Subscriptions do
  @moduledoc """
  Subscriptions holds state for subscribers interested in events appended to either a single stream or all streams
  """

  use GenServer
  require Logger

  alias EventStore.Subscriptions
  alias EventStore.Subscriptions.Subscription

  defstruct all_stream: [], single_stream: %{}, supervisor: nil

  @all_stream "$all"

  def start_link do
    GenServer.start_link(__MODULE__, %Subscriptions{}, name: __MODULE__)
  end

  def subscribe_to_stream(stream_uuid, stream, subscription_name, subscriber) do
    GenServer.call(__MODULE__, {:subscribe_to_stream, stream_uuid, stream, subscription_name, subscriber})
  end

  def unsubscribe_from_stream(stream_uuid, subscription_name) do
    GenServer.call(__MODULE__, {:unsubscribe_from_stream, stream_uuid, subscription_name})
  end

  def notify_events(stream_uuid, events) do
    GenServer.cast(__MODULE__, {:notify_events, stream_uuid, events})
  end

  def init(%Subscriptions{} = subscriptions) do
    {:ok, supervisor} = Subscriptions.Supervisor.start_link

    subscriptions = %Subscriptions{subscriptions | supervisor: supervisor}

    {:ok, subscriptions}
  end

  def handle_call({:subscribe_to_stream, stream_uuid, stream, subscription_name, subscriber}, _from, %Subscriptions{supervisor: supervisor} = subscriptions) do
    # TODO: Ensure subscription is not already present in single/all stream subscriptions

    {:ok, subscription} = Subscriptions.Supervisor.subscribe_to_stream(supervisor, stream_uuid, stream, subscription_name, subscriber)

    Process.monitor(subscription)

    subscriptions = case stream_uuid do
      @all_stream -> append_all_stream_subscription(subscriptions, subscription)
      stream_uuid -> append_single_stream_subscription(subscriptions, subscription, stream_uuid)
    end

    {:reply, {:ok, subscription}, subscriptions}
  end

  def handle_call({:unsubscribe_from_stream, stream_uuid, subscription_name}, _from, %Subscriptions{} = state) do
    # TODO: Shutdown subscription process and delete subscription from storage

    state = remove_subscription(state, stream_uuid, subscription_name)

    {:reply, :ok, state}
  end

  def handle_cast({:notify_events, stream_uuid, events}, %Subscriptions{all_stream: all_stream, single_stream: single_stream} = subscriptions) do
    interested_subscriptions = all_stream ++ Map.get(single_stream, stream_uuid, [])

    interested_subscriptions
    |> Enum.each(&Subscription.notify_events(&1, events))

    {:noreply, subscriptions}
  end

  def handle_info({:DOWN, _ref, :process, pid, reason}, %Subscriptions{all_stream: all_stream, single_stream: single_stream} = subscriptions) do
    Logger.warn "subscription down due to: #{reason}"

    all_stream = List.delete(all_stream, pid)
    single_stream = single_stream
      |> Enum.map(fn {key, value} -> {key, List.delete(value, pid)} end)
      |> Map.new

    {:noreply, %Subscriptions{subscriptions | all_stream: all_stream, single_stream: single_stream}}
  end

  defp append_all_stream_subscription(%Subscriptions{all_stream: all_stream} = subscriptions, subscription) do
    %Subscriptions{subscriptions | all_stream: [subscription | all_stream]}
  end

  defp append_single_stream_subscription(%Subscriptions{single_stream: single_stream} = subscriptions, subscription, stream_uuid) do
    {_, single_stream} = Map.get_and_update(single_stream, stream_uuid, fn current_value ->
      new_value = case current_value do
        nil -> [subscription]
        current_value -> [subscription | current_value]
      end

      {current_value, new_value}
    end)

    %Subscriptions{subscriptions | single_stream: single_stream}
  end

  defp remove_subscription(%Subscriptions{all_stream: _all_stream, single_stream: _single_stream} = state, _stream_uuid, _subscription_name) do
    state
  end

  defp remove_all_stream_subscription(%Subscriptions{all_stream: _all_stream} = state, _subscription_name) do
    state
  end
end
