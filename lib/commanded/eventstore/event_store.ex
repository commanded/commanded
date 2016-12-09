defmodule Commanded.EventStore do

  alias Commanded.EventStore.{EventData, RecordedEvent, SnapshotData}

  defmacro __using__(_) do
    quote do
      @event_store Commanded.EventStore.Adapters.PostgresEventStore
    end
  end
  
  @callback append_to_stream(String.t, non_neg_integer, list(EventData.t)) :: :ok | {:error, reason :: term}

  @callback read_snapshot(String.t) :: {:ok, SnapshotData.t} | {:error, :snapshot_not_found}
  
  @callback read_stream_forward(String.t) :: {:ok, list(RecordedEvent.t)} | {:error, reason :: term}
  @callback read_stream_forward(String.t, non_neg_integer) :: {:ok, list(RecordedEvent.t)} | {:error, reason :: term}
  @callback read_stream_forward(String.t, non_neg_integer, non_neg_integer) :: {:ok, list(RecordedEvent.t)} | {:error, reason :: term}
  
  @callback subscribe_to_all_streams(String.t, pid) :: {:ok, subscription :: any}

  @callback unsubscribe_from_all_streams(String.t) :: :ok

  @callback record_snapshot(SnapshotData.t) :: :ok | {:error, reason :: term}

  @callback ack_events(subscription :: any, non_neg_integer) :: :ok

  @callback read_all_streams_forward() :: {:ok, list(RecordedEvent.t)} | {:error, reason :: term}
  @callback read_all_streams_forward(non_neg_integer) :: {:ok, list(RecordedEvent.t)} | {:error, reason :: term}
  @callback read_all_streams_forward(non_neg_integer, non_neg_integer) :: {:ok, list(RecordedEvent.t)} | {:error, reason :: term}
  
end
