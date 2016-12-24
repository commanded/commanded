defmodule Commanded.EventStore do

  alias Commanded.EventStore.{EventData, RecordedEvent, SnapshotData}

  defmacro __using__(_) do
    mapping = %{
      Extreme              => Commanded.EventStore.Adapters.ExtremeEventStore,
      EventStore           => Commanded.EventStore.Adapters.EventStoreEventStore,
    }

    default_adapter =
      Map.get(
	mapping,
	Enum.find(Map.keys(mapping), &Code.ensure_loaded?(&1)),
	:no_event_store_loaded
      )
    
    adapter = Application.get_env(:commanded, :event_store_adapter, default_adapter)

    quote do
      @event_store unquote adapter
    end
  end

  @type start_from :: :origin | :current | integer
  
  @callback append_to_stream(String.t, non_neg_integer, list(EventData.t)) :: :ok | {:error, reason :: term}

  @callback read_snapshot(String.t) :: {:ok, SnapshotData.t} | {:error, :snapshot_not_found}
  
  @callback read_stream_forward(String.t) :: {:ok, list(RecordedEvent.t)} | {:error, reason :: term}
  @callback read_stream_forward(String.t, non_neg_integer) :: {:ok, list(RecordedEvent.t)} | {:error, reason :: term}
  @callback read_stream_forward(String.t, non_neg_integer, non_neg_integer) :: {:ok, list(RecordedEvent.t)} | {:error, reason :: term}
  
  @callback subscribe_to_all_streams(String.t, pid, start_from) :: {:ok, subscription :: any}
    | {:error, :subscription_already_exists}
    | {:error, reason :: term}

  @callback unsubscribe_from_all_streams(String.t) :: :ok

  @callback record_snapshot(SnapshotData.t) :: :ok | {:error, reason :: term}

  @callback read_all_streams_forward() :: {:ok, list(RecordedEvent.t)} | {:error, reason :: term}
  @callback read_all_streams_forward(non_neg_integer) :: {:ok, list(RecordedEvent.t)} | {:error, reason :: term}
  @callback read_all_streams_forward(non_neg_integer, non_neg_integer) :: {:ok, list(RecordedEvent.t)} | {:error, reason :: term}

  @callback delete_snapshot(String.t) :: :ok | {:error, reason :: term}
  
end
