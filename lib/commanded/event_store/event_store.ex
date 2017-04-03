defmodule Commanded.EventStore do
  @moduledoc """
  Defines the behaviour to be implemented by an event store adapter to be used by Commanded.
  """

  alias Commanded.EventStore.{
    EventData,
    RecordedEvent,
    SnapshotData,
  }

  defmacro __using__(_) do
    adapter = Application.get_env(:commanded, :event_store_adapter, Commanded.EventStore.Adapters.InMemory)

    quote do
      @event_store unquote adapter
    end
  end

  @type stream_uuid :: String.t
  @type start_from :: :origin | :current | integer
  @type stream_version :: integer
  @type subscription_name :: String.t
  @type source_uuid :: String.t
  @type reason :: term

  @doc """
  Append one or more events to a stream atomically.
  """
  @callback append_to_stream(stream_uuid, expected_version :: non_neg_integer, events :: list(EventData.t)) :: {:ok, stream_version} | {:error, reason}

  @doc """
  Streams events from the given stream, in the order in which they were originally written.
  """
  @callback stream_forward(stream_uuid, start_version :: non_neg_integer, read_batch_size :: non_neg_integer) :: Enumerable.t | {:error, reason}

  @doc """
  Subscriber will be notified of every event persisted to any stream.
  """
  @callback subscribe_to_all_streams(subscription_name, subscriber :: pid, start_from) :: {:ok, subscription :: any}
    | {:error, :subscription_already_exists}
    | {:error, reason}

  @callback ack_event(pid, RecordedEvent.t) :: any

  @doc """
  Unsubscribe an existing subscriber from all event notifications.
  """
  @callback unsubscribe_from_all_streams(subscription_name) :: :ok

  @doc """
  Read a snapshot, if available, for a given source.
  """
  @callback read_snapshot(source_uuid) :: {:ok, SnapshotData.t} | {:error, :snapshot_not_found}

  @doc """
  Record a snapshot of the data and metadata for a given source
  """
  @callback record_snapshot(source_uuid) :: :ok | {:error, reason}

  @doc """
  Delete a previously recorded snapshop for a given source
  """
  @callback delete_snapshot(source_uuid) :: :ok | {:error, reason}
end
