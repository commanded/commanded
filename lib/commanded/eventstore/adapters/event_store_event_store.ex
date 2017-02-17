if Code.ensure_loaded?(EventStore) do 
defmodule Commanded.EventStore.Adapters.EventStoreEventStore do

  @behaviour Commanded.EventStore

  use GenServer

  require Logger

  alias Commanded.EventStore.{EventData, RecordedEvent, SnapshotData}
  alias Commanded.EventStore.Adapters.EventStoreSubscription

  def start_link() do
    state = %{subscriptions: %{}}

    GenServer.start_link(__MODULE__, state, [name: __MODULE__])
  end

  @spec ack_event(pid, RecordedEvent.t) :: any
  def ack_event(subscription, %RecordedEvent{} = last_seen_event) do
    send(subscription, {:ack, last_seen_event.event_id})
  end
  
  @spec append_to_stream(String.t, non_neg_integer, list(EventData.t)) :: :ok | {:error, reason :: term}
  def append_to_stream(stream_uuid, expected_version, events) do
    result = EventStore.append_to_stream(
      stream_uuid,
      expected_version,
      Enum.map(events, &to_pg_event_data(&1))
    )

    case result do
      :ok -> {:ok, expected_version + length(events)}
      err -> err
    end
  end

  @spec record_snapshot(SnapshotData.t) :: :ok | {:error, reason :: term}
  def record_snapshot(snapshot = %SnapshotData{}) do
    EventStore.record_snapshot(to_pg_snapshot_data(snapshot))
  end

  @spec read_snapshot(String.t) :: {:ok, SnapshotData.t} | {:error, :snapshot_not_found}
  def read_snapshot(source_uuid) do
    case EventStore.read_snapshot(source_uuid) do
      {:ok, snapshot_data} -> {:ok, from_pg_snapshot_data(snapshot_data)}
      err -> err
    end
  end
  
  @spec read_stream_forward(String.t, non_neg_integer, non_neg_integer) :: {:ok, list(RecordedEvent.t)} | {:error, reason :: term}
  def read_stream_forward(stream_uuid, start_version \\ 0, count \\ 1_000) do
    case EventStore.read_stream_forward(stream_uuid, start_version, count) do
      {:ok, events} -> {:ok, Enum.map(events, &from_pg_recorded_event(&1))}
      err -> err
    end
  end  

  @spec stream_forward(String.t, non_neg_integer, non_neg_integer) :: Enumerable.t | {:error, reason :: term}
  def stream_forward(stream_uuid, start_version \\ 0, read_batch_size \\ 1_000) do
    case EventStore.stream_forward(stream_uuid, start_version, read_batch_size) do
      {:error, :stream_not_found}=err -> Stream.map([err], &(&1))
      {:error, reason} -> {:error, reason}
      stream ->	stream |> Stream.map(&from_pg_recorded_event/1)
    end
  end
  
  @spec read_all_streams_forward(non_neg_integer, non_neg_integer) :: {:ok, list(RecordedEvent.t)} | {:error, reason :: term}
  def read_all_streams_forward(start_event_id \\ 0, count \\ 1_000) do
    case EventStore.read_all_streams_forward(start_event_id, count) do
      {:ok, events} -> {:ok, Enum.map(events, &from_pg_recorded_event(&1))}
      err -> err
    end
  end

  @spec subscribe_to_all_streams(String.t, pid, Commanded.EventStore.start_from) :: {:ok, subscription :: any}
    | {:error, :subscription_already_exists}
    | {:error, reason :: term}
  def subscribe_to_all_streams(subscription_name, subscriber, start_from \\ :origin) do
    GenServer.call(__MODULE__, {:subscribe_all, subscription_name, subscriber, start_from})
  end

  @spec unsubscribe_from_all_streams(String.t) :: :ok
  def unsubscribe_from_all_streams(subscription_name) do
    GenServer.call(__MODULE__, {:unsubscribe_all, subscription_name})
  end

  @spec delete_snapshot(String.t) :: :ok | {:error, reason :: term}
  def delete_snapshot(source_uuid) do
    EventStore.delete_snapshot(source_uuid)
  end

  def handle_call({:unsubscribe_all, subscription_name}, _from, state) do
    {subscription_pid, subscriptions} = Map.pop(state.subscriptions, subscription_name)

    EventStore.unsubscribe_from_all_streams(subscription_name)
    Process.exit(subscription_pid, :kill)

    {:reply, :ok, %{state | subscriptions: subscriptions}}
  end

  def handle_call({:subscribe_all, subscription_name, subscriber, start_from}, _from, state) do
    {:ok, pid} = EventStoreSubscription.start(subscription_name, subscriber, start_from)
    state = %{ state | subscriptions: Map.put(state.subscriptions, subscription_name, pid)}

    {:reply, EventStoreSubscription.result(pid), state}
  end

  def to_pg_snapshot_data(snapshot = %SnapshotData{}) do
    struct(EventStore.Snapshots.SnapshotData, Map.from_struct(snapshot))
  end
  
  def to_pg_event_data(event_data = %EventData{}) do
    struct(EventStore.EventData, Map.from_struct(event_data))
  end

  def from_pg_snapshot_data(snapshot_data = %EventStore.Snapshots.SnapshotData{}) do
    struct(SnapshotData, Map.from_struct(snapshot_data))
  end

  def from_pg_recorded_event(recorded_event = %EventStore.RecordedEvent{}) do
    struct(RecordedEvent, Map.from_struct(recorded_event))
  end
end
end
