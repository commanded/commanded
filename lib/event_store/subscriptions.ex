defmodule EventStore.Subscriptions do
  @moduledoc """
  Subscriptions holds state for subscribers interested in events appended to either a single stream or all streams
  """

  use GenServer
  use EventStore.Serializer

  require Logger

  alias EventStore.{RecordedEvent,Subscriptions}
  alias EventStore.Subscriptions.{Subscription}

  defstruct [
    all_stream: %{},
    single_stream: %{},
    subscription_pids: %{},
    supervisor: nil,
  ]

  @all_stream "$all"

  def start_link do
    GenServer.start_link(__MODULE__, %Subscriptions{}, name: __MODULE__)
  end

  def subscribe_to_stream(stream_uuid, subscription_name, subscriber, opts \\ [])
  def subscribe_to_stream(stream_uuid, subscription_name, subscriber, opts) do
    GenServer.call(__MODULE__, {:subscribe_to_stream, stream_uuid, subscription_name, subscriber, opts})
  end

  def subscribe_to_all_streams(subscription_name, subscriber, opts \\ [])
  def subscribe_to_all_streams(subscription_name, subscriber, opts) do
    GenServer.call(__MODULE__, {:subscribe_to_stream, @all_stream, subscription_name, subscriber, opts})
  end

  def unsubscribe_from_stream(stream_uuid, subscription_name) do
    GenServer.call(__MODULE__, {:unsubscribe_from_stream, stream_uuid, subscription_name})
  end

  def unsubscribe_from_all_streams(subscription_name) do
    GenServer.call(__MODULE__, {:unsubscribe_from_stream, @all_stream, subscription_name})
  end

  def notify_events(stream_uuid, events) do
    GenServer.cast(__MODULE__, {:notify_events, stream_uuid, events})
  end

  def init(%Subscriptions{} = subscriptions) do
    {:ok, supervisor} = Subscriptions.Supervisor.start_link

    subscriptions = %Subscriptions{subscriptions | supervisor: supervisor}

    {:ok, subscriptions}
  end

  def handle_call({:subscribe_to_stream, stream_uuid, subscription_name, subscriber, opts}, _from, %Subscriptions{supervisor: supervisor} = subscriptions) do
    reply = case get_subscription(stream_uuid, subscription_name, subscriptions) do
      nil -> create_subscription(supervisor, stream_uuid, subscription_name, subscriber, opts)
      _subscription -> {:error, :subscription_already_exists}
    end

    subscriptions = case reply do
      {:ok, subscription} -> append_subscription(stream_uuid, subscription_name, subscription, subscriptions)
      _ -> subscriptions
    end

    {:reply, reply, subscriptions}
  end

  def handle_call({:unsubscribe_from_stream, stream_uuid, subscription_name}, _from, %Subscriptions{supervisor: supervisor} = subscriptions) do
    subscriptions = case get_subscription(stream_uuid, subscription_name, subscriptions) do
      nil -> subscriptions
      subscription ->
        delete_subscription(supervisor, subscription)
        remove_subscription(subscriptions, stream_uuid, subscription_name, subscription)
    end

    {:reply, :ok, subscriptions}
  end

  def handle_cast({:notify_events, stream_uuid, recorded_events}, %Subscriptions{all_stream: all_stream, single_stream: single_stream} = subscriptions) do
    interested_subscriptions = Map.values(all_stream) ++ Map.values(Map.get(single_stream, stream_uuid, %{}))

    notify_subscribers(interested_subscriptions, recorded_events)

    {:noreply, subscriptions}
  end

  def handle_info({:DOWN, _ref, :process, pid, reason}, %Subscriptions{subscription_pids: subscription_pids} = subscriptions) do
    _ = Logger.info(fn -> "subscription down due to: #{inspect reason}" end)

    subscriptions = case Map.get(subscription_pids, pid) do
      nil -> subscriptions
      {stream_uuid, subscription_name} -> remove_subscription(subscriptions, stream_uuid, subscription_name, pid)
    end

    {:noreply, subscriptions}
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

  defp create_subscription(supervisor, stream_uuid, subscription_name, subscriber, opts) do
    _ = Logger.debug(fn -> "creating subscription process on stream #{inspect stream_uuid} named: #{inspect subscription_name}" end)

    {:ok, subscription} = Subscriptions.Supervisor.subscribe_to_stream(supervisor, stream_uuid, subscription_name, subscriber, opts)

    Process.monitor(subscription)

    {:ok, subscription}
  end

  defp delete_subscription(supervisor, subscription) do
    :ok = Subscription.unsubscribe(subscription)
    :ok = Subscriptions.Supervisor.unsubscribe_from_stream(supervisor, subscription)
  end

  defp append_subscription(@all_stream, subscription_name, subscription, %Subscriptions{all_stream: all_stream, subscription_pids: subscription_pids} = subscriptions) do
    all_stream = Map.put(all_stream, subscription_name, subscription)
    subscription_pids = Map.put(subscription_pids, subscription, {@all_stream, subscription_name})

    %Subscriptions{subscriptions | all_stream: all_stream, subscription_pids: subscription_pids}
  end

  defp append_subscription(stream_uuid, subscription_name, subscription, %Subscriptions{single_stream: single_stream, subscription_pids: subscription_pids} = subscriptions) do
    {_, single_stream} = Map.get_and_update(single_stream, stream_uuid, fn stream_subscriptions ->
      updated = Map.put(stream_subscriptions || %{}, subscription_name, subscription)
      {stream_subscriptions, updated}
    end)
    subscription_pids = Map.put(subscription_pids, subscription, {stream_uuid, subscription_name})

    %Subscriptions{subscriptions | single_stream: single_stream, subscription_pids: subscription_pids}
  end

  defp notify_subscribers([], _recorded_events), do: nil
  defp notify_subscribers(_subscriptions, []), do: nil
  defp notify_subscribers(subscriptions, recorded_events) do
    events = Enum.map(recorded_events, &RecordedEvent.deserialize/1)

    subscriptions
    |> Enum.each(&Subscription.notify_events(&1, events))
  end

  defp remove_subscription(%Subscriptions{} = subscriptions, stream_uuid, subscription_name, subscription) do
    subscriptions
    |> remove_subscription(stream_uuid, subscription_name)
    |> remove_subscription_pid(subscription)
  end

  defp remove_subscription(%Subscriptions{all_stream: all_stream} = subscriptions, @all_stream, subscription_name) do
    all_stream = Map.delete(all_stream, subscription_name)

    %Subscriptions{subscriptions | all_stream: all_stream}
  end

  defp remove_subscription(%Subscriptions{single_stream: single_stream} = subscriptions, stream_uuid, subscription_name) do
    single_stream = Map.update(single_stream, stream_uuid, %{}, &Map.delete(&1, subscription_name))

    %Subscriptions{subscriptions | single_stream: single_stream}
  end

  defp remove_subscription_pid(%Subscriptions{subscription_pids: subscription_pids} = subscriptions, pid) do
    %Subscriptions{subscriptions | subscription_pids: Map.delete(subscription_pids, pid)}
  end
end
