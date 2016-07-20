defmodule EventStore.Subscriptions do
  @moduledoc """
  Subscriptions holds state for subscribers interested in events appended to either a single stream or all streams
  """

  use GenServer
  require Logger

  alias EventStore.{RecordedEvent,Subscriptions}
  alias EventStore.Subscriptions.{Subscription,SubscriptionData}

  defstruct all_stream: %{}, single_stream: %{}, supervisor: nil, serializer: nil

  @all_stream "$all"

  def start_link(serializer) do
    GenServer.start_link(__MODULE__, %Subscriptions{serializer: serializer}, name: __MODULE__)
  end

  def subscribe_to_stream(stream_uuid, stream, subscription_name, subscriber) do
    GenServer.call(__MODULE__, {:subscribe_to_stream, stream_uuid, stream, subscription_name, subscriber})
  end

  def subscribe_to_all_streams(all_stream, subscription_name, subscriber) do
    GenServer.call(__MODULE__, {:subscribe_to_stream, @all_stream, all_stream, subscription_name, subscriber})
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
    reply = case get_subscription(stream_uuid, subscription_name, subscriptions) do
      nil -> create_subscription(supervisor, stream_uuid, stream, subscription_name, subscriber)
      subscription -> {:error, :subscription_already_exists}
    end

    subscriptions = case reply do
      {:ok, subscription} -> append_subscription(stream_uuid, subscription_name, subscription, subscriptions)
      _ -> subscriptions
    end

    {:reply, reply, subscriptions}
  end

  def handle_call({:unsubscribe_from_stream, stream_uuid, subscription_name}, _from, %Subscriptions{} = subscriptions) do
    # TODO: Shutdown subscription process and delete subscription from storage

    state = remove_subscription(stream_uuid, subscription_name, subscriptions)

    {:reply, :ok, state}
  end

  def handle_cast({:notify_events, stream_uuid, recorded_events}, %Subscriptions{all_stream: all_stream, single_stream: single_stream, serializer: serializer} = subscriptions) do
    interested_subscriptions = Map.values(all_stream) ++ Map.values(Map.get(single_stream, stream_uuid, %{}))

    notify_subscribers(interested_subscriptions, recorded_events, serializer)

    {:noreply, subscriptions}
  end

  def handle_info({:DOWN, _ref, :process, pid, reason}, %Subscriptions{all_stream: all_stream, single_stream: single_stream} = subscriptions) do
    Logger.warn "subscription down due to: #{reason}"

    all_stream =
      all_stream
      |> Enum.map(fn {key, value} -> {key, List.delete(value, pid)} end)
      |> Map.new

    single_stream =
      single_stream
      |> Enum.map(fn {key, value} -> {key, List.delete(value, pid)} end)
      |> Map.new

    {:noreply, %Subscriptions{subscriptions | all_stream: all_stream, single_stream: single_stream}}
  end

  defp get_subscription(@all_stream, subscription_name, %Subscriptions{all_stream: all_stream}) do
    Map.get(all_stream, subscription_name)
  end

  defp get_subscription(stream_uuid, subscription_name, %Subscriptions{single_stream: single_stream}) do
    case Map.get(single_stream, stream_uuid) do
      nil -> nil
      subscriptions -> Map.get(subscriptions, subscription_name)
    end
  end

  defp create_subscription(supervisor, stream_uuid, stream, subscription_name, subscriber) do
    {:ok, subscription} = Subscriptions.Supervisor.subscribe_to_stream(supervisor, stream_uuid, stream, subscription_name, subscriber)

    Process.monitor(subscription)

    {:ok, subscription}
  end

  defp append_subscription(@all_stream, subscription_name, subscription, %Subscriptions{all_stream: all_stream} = subscriptions) do
    all_stream = Map.put(all_stream, subscription_name, subscription)

    %Subscriptions{subscriptions | all_stream: all_stream}
  end

  defp append_subscription(stream_uuid, subscription_name, subscription, %Subscriptions{single_stream: single_stream} = subscriptions) do
    {_, single_stream} = Map.get_and_update(single_stream, stream_uuid, fn stream_subscriptions ->
      updated = Map.put(stream_subscriptions || %{}, subscription_name, subscription)
      {stream_subscriptions, updated}
    end)

    %Subscriptions{subscriptions | single_stream: single_stream}
  end

  defp notify_subscribers([], _recorded_events, _serializer), do: nil
  defp notify_subscribers(subscriptions, recorded_events, serializer) do
    events = Enum.map(recorded_events, fn event -> deserialize_recorded_event(event, serializer) end)

    subscriptions
    |> Enum.each(&Subscription.notify_events(&1, events))
  end

  defp deserialize_recorded_event(%RecordedEvent{data: data, metadata: metadata, event_type: event_type} = recorded_event, serializer) do
    %RecordedEvent{recorded_event |
      data: serializer.deserialize(data, type: event_type),
      metadata: serializer.deserialize(metadata, [])
    }
  end

  defp remove_subscription(@all_stream, _subscription_name, %Subscriptions{all_stream: _all_stream} = subscriptions) do
    subscriptions
  end

  defp remove_all_stream_subscription(_stream_uuid, _subscription_name, %Subscriptions{single_stream: _single_stream} = subscriptions) do
    subscriptions
  end
end
