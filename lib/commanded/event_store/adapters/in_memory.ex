defmodule Commanded.EventStore.Adapters.InMemory do
  @moduledoc """
  An in-memory event store adapter useful for testing as no persistence provided.
  """

  @behaviour Commanded.EventStore

  use GenServer

  defstruct [
    streams: %{},
    subscriptions: %{},
    snapshots: %{},
  ]

  defmodule Subscription do
    defstruct [
      name: nil,
      subscriber: nil,
      start_from: nil,
    ]
  end

  alias Commanded.EventStore.Adapters.InMemory
  alias Commanded.EventStore.Adapters.InMemory.Subscription
  alias Commanded.EventStore.SnapshotData

  def start_link do
    GenServer.start_link(__MODULE__, %InMemory{}, name: __MODULE__)
  end

  def init(%InMemory{} = state) do
    {:ok, state}
  end

  def append_to_stream(stream_uuid, expected_version, events) do
    GenServer.call(__MODULE__, {:append_to_stream, stream_uuid, expected_version, events})
  end

  def stream_forward(stream_uuid, start_version \\ 0, read_batch_size \\ 1_000)
  def stream_forward(stream_uuid, start_version, _read_batch_size) do
    GenServer.call(__MODULE__, {:stream_forward, stream_uuid, start_version})
  end

  def subscribe_to_all_streams(subscription_name, subscriber, start_from) do
    subscription = %Subscription{name: subscription_name, subscriber: subscriber, start_from: start_from}

    GenServer.call(__MODULE__, {:subscribe_to_all_streams, subscription})
  end

  def ack_event(pid, event) do
    :ok
  end

  def unsubscribe_from_all_streams(subscription_name) do
    GenServer.call(__MODULE__, {:unsubscribe_from_all_streams, subscription_name})
  end

  def read_snapshot(source_uuid) do
    GenServer.call(__MODULE__, {:read_snapshot, source_uuid})
  end

  def record_snapshot(snapshot) do
    GenServer.call(__MODULE__, {:record_snapshot, snapshot})
  end

  def delete_snapshot(source_uuid) do
    GenServer.call(__MODULE__, {:delete_snapshot, source_uuid})
  end

  def handle_call({:append_to_stream, stream_uuid, expected_version, events}, _from, %InMemory{streams: streams} = state) do
    case Map.get(streams, stream_uuid) do
      nil ->
        case expected_version do
          0 ->
            state = %InMemory{state | streams: Map.put(streams, stream_uuid, events)}

            publish(events, state)

            {:reply, {:ok, length(events)}, state}
          _ -> {:reply, {:error, :wrong_expected_version}, state}
        end

      existing_events when length(existing_events) != expected_version ->
        {:reply, {:error, :wrong_expected_version}, state}

      existing_events ->
        stream_events = existing_events ++ events

        state = %InMemory{state |
          streams: Map.put(streams, stream_uuid, stream_events),
        }

        publish(events, state)

        {:reply, {:ok, length(stream_events)}, state}
    end
  end

  def handle_call({:stream_forward, stream_uuid, start_version}, _from, %InMemory{streams: streams} = state) do
    event_stream =
      streams
      |> Map.get(stream_uuid, [])
      |> Stream.drop(max(0, start_version - 1))

    {:reply, event_stream, state}
  end

  def handle_call({:subscribe_to_all_streams, %Subscription{name: subscription_name, subscriber: subscriber, start_from: start_from} = subscription}, _from, %InMemory{subscriptions: subscriptions} = state) do
    {reply, state} = case Map.get(subscriptions, subscription_name) do
      nil ->
        state = %InMemory{state |
          subscriptions: Map.put(subscriptions, subscription_name, subscription),
        }

        {{:ok, self()}, state}
      subscription -> {{:error, :subscription_already_exists}, state}
    end

    {:reply, reply, state}
  end

  def handle_call({:unsubscribe_from_all_streams, subscription_name}, _from, %InMemory{subscriptions: subscriptions} = state) do
    state = %InMemory{state |
      subscriptions: Map.delete(subscriptions, subscription_name),
    }

    {:reply, :ok, state}
  end

  def handle_call({:read_snapshot, source_uuid}, _from, %InMemory{snapshots: snapshots} = state) do
    reply = case Map.get(snapshots, source_uuid, nil) do
      nil -> {:error, :snapshot_not_found}
      snapshot -> {:ok, snapshot}
    end

    {:reply, reply, state}
  end

  def handle_call({:read_snapshot, source_uuid}, _from, %InMemory{snapshots: snapshots} = state) do
    reply = case Map.get(snapshots, source_uuid, nil) do
      nil -> {:error, :snapshot_not_found}
      snapshot -> {:ok, snapshot}
    end

    {:reply, reply, state}
  end

  def handle_call({:record_snapshot, %SnapshotData{source_uuid: source_uuid} = snapshot}, _from, %InMemory{snapshots: snapshots} = state) do
    state = %InMemory{state |
      snapshots: Map.put(snapshots, source_uuid, snapshot),
    }

    {:reply, :ok, state}
  end

  def handle_call({:delete_snapshot, source_uuid}, _from, %InMemory{snapshots: snapshots} = state) do
    state = %InMemory{state |
      snapshots: Map.delete(snapshots, source_uuid)
    }

    {:reply, :ok, state}
  end

  # publish events to subscribers
  defp publish(events, %InMemory{subscriptions: subscriptions}) do
    for %Subscription{subscriber: subscriber} <- Map.values(subscriptions), do: send(subscriber, {:events, events})
  end
end
