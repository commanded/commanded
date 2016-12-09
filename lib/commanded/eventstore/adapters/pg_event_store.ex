defmodule Commanded.EventStore.Adapters.PostgresEventStore do

  @behaviour Commanded.EventStore

  require Logger

  alias Commanded.EventStore.{EventData, RecordedEvent, SnapshotData}
  alias Commanded.EventStore.Adapters.PostgresSubscription
  
  @spec append_to_stream(String.t, non_neg_integer, list(EventData.t)) :: :ok | {:error, reason :: term}
  def append_to_stream(stream_uuid, expected_version, events) do
    Logger.debug("append to stream")

    EventStore.append_to_stream(
      stream_uuid,
      expected_version,
      Enum.map(events, &to_pg_event_data(&1))
    )
  end

  @spec read_snapshot(String.t) :: {:ok, SnapshotData.t} | {:error, :snapshot_not_found}
  def read_snapshot(source_uuid) do
    case EventStore.read_snapshot(source_uuid) do
      {:ok, snapshot_data} -> {:ok, from_pg_snapshot_data(snapshot_data)}
      err -> err
    end
  end
  
  @spec read_stream_forward(String.t) :: {:ok, list(RecordedEvent.t)} | {:error, reason :: term}
  @spec read_stream_forward(String.t, non_neg_integer) :: {:ok, list(RecordedEvent.t)} | {:error, reason :: term}
  @spec read_stream_forward(String.t, non_neg_integer, non_neg_integer) :: {:ok, list(RecordedEvent.t)} | {:error, reason :: term}
  def read_stream_forward(stream_uuid, start_version \\ 0, count \\ 1_000) do
    case EventStore.read_stream_forward(stream_uuid, start_version, count) do
      {:ok, events} -> {:ok, Enum.map(events, &from_pg_recorded_event(&1))}
      err -> err
    end
  end  
  
  @spec record_snapshot(SnapshotData.t) :: :ok | {:error, reason :: term}
  def record_snapshot(snapshot = %SnapshotData{}) do
    EventStore.record_snapshot(to_pg_snapshot_data(snapshot))
  end

  @callback read_all_streams_forward() :: {:ok, list(RecordedEvent.t)} | {:error, reason :: term}
  @callback read_all_streams_forward(non_neg_integer) :: {:ok, list(RecordedEvent.t)} | {:error, reason :: term}
  @callback read_all_streams_forward(non_neg_integer, non_neg_integer) :: {:ok, list(RecordedEvent.t)} | {:error, reason :: term}
  def read_all_streams_forward(start_event_id \\ 0, count \\ 1_000) do
    case EventStore.read_all_streams_forward(start_event_id, count) do
      {:ok, events} -> {:ok, Enum.map(events, &from_pg_recorded_event(&1))}
      err -> err
    end
  end

  @spec subscribe_to_all_streams(String.t, pid) :: {:ok, subscription :: any}
  def subscribe_to_all_streams(subscription_name, subscriber) do
    {:ok, pid} = PostgresSubscription.start_link(subscription_name, subscriber)

    PostgresSubscription.result(pid)
  end

  @spec unsubscribe_from_all_streams(String.t) :: :ok
  def unsubscribe_from_all_streams(subscription_name) do
    EventStore.unsubscribe_from_all_streams(subscription_name)
    :ok
  end

  @spec ack_events(subscription :: any, non_neg_integer) :: :ok
  def ack_events(subscription, last_seen_event_id) do
    PostgresSubscription.ack_events(subscription.pid, last_seen_event_id)
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
