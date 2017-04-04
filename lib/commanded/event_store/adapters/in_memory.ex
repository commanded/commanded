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

  def stream_forward(stream_uuid, start_version, read_batch_size) do
    []
  end

  def subscribe_to_all_streams(subscription_name, subscriber, start_from) do
    subscription = %Subscription{name: subscription_name, subscriber: subscriber, start_from: start_from}

    {:ok, subscription}
  end

  def ack_event(pid, event) do
    :ok
  end

  def unsubscribe_from_all_streams(subscription_name) do
    :ok
  end

  def read_snapshot(source_uuid) do
    {:ok, %SnapshotData{}}
  end

  def record_snapshot(source_uuid) do
    :ok
  end

  def delete_snapshot(source_uuid) do
    :ok
  end

  def handle_call({:append_to_stream, stream_uuid, expected_version, events}, _from, %InMemory{streams: streams} = state) do
    case Map.get(streams, stream_uuid) do
      nil ->
        case expected_version do
          0 -> {:reply, {:ok, length(events)}, %InMemory{state | streams: Map.put(streams, stream_uuid, events)}}
          _ -> {:reply, {:error, :wrong_expected_version}, state}
        end

      persisted_events when length(persisted_events) != expected_version ->
        {:reply, {:error, :wrong_expected_version}, state}

      persisted_events ->
        state = %InMemory{state |
          streams: Map.put(streams, stream_uuid, persisted_events ++ events),
        }

        {:reply, {:ok, expected_version + length(events)}, state}
    end
  end
end
