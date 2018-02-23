defmodule Commanded.EventStore do
  @moduledoc """
  Defines the behaviour to be implemented by an event store adapter to be used by Commanded.
  """

  alias Commanded.EventStore.{
    EventData,
    RecordedEvent,
    SnapshotData,
  }

  @type stream_uuid :: String.t
  @type start_from :: :origin | :current | integer
  @type stream_version :: integer
  @type subscription_name :: String.t
  @type source_uuid :: String.t
  @type snapshot :: SnapshotData.t
  @type reason :: term

  @doc """
  Append one or more events to a stream atomically.
  """
  @callback append_to_stream(stream_uuid, expected_version :: non_neg_integer, events :: list(EventData.t)) :: {:ok, stream_version}
    | {:error, :wrong_expected_version}
    | {:error, reason}

  @doc """
  Streams events from the given stream, in the order in which they were
  originally written.
  """
  @callback stream_forward(stream_uuid, start_version :: non_neg_integer, read_batch_size :: non_neg_integer) :: Enumerable.t
    | {:error, :stream_not_found}
    | {:error, reason}

  @doc """
  Create a transient subscription to a single event stream.

  The event store will publish any events appended to the given stream to the
  `subscriber` process as an `{:events, events}` message.

  The subscriber does not need to acknowledge receipt of the events.
  """
  @callback subscribe(stream_uuid) :: :ok | {:error, reason}

  @doc """
  Create a persistent subscription to all event streams.

  The event store will remember the subscribers last acknowledged event.
  Restarting the named subscription will resume from the next event following
  the last seen.

  Once subscribed, the subscriber process should be sent a
  `{:subscribed, subscription}` message to allow it to defer initialisation
  until the subscription has started.

  The subscriber process will be sent all events persisted to any stream. It
  will receive a `{:events, events}` message for each batch of events persisted
  for a single aggregate.

  The subscriber must ack each received, and successfully processed event, using
  `Commanded.EventStore.ack_event/2`.
  """
  @callback subscribe_to_all_streams(subscription_name, subscriber :: pid, start_from) :: {:ok, subscription :: pid}
    | {:error, :subscription_already_exists}
    | {:error, reason}

  @doc """
  Acknowledge receipt and successful processing of the given event received from
  a subscription to an event stream.
  """
  @callback ack_event(pid, RecordedEvent.t) :: :ok

  @doc """
  Unsubscribe an existing subscriber from all event notifications.
  """
  @callback unsubscribe_from_all_streams(subscription_name) :: :ok

  @doc """
  Read a snapshot, if available, for a given source.
  """
  @callback read_snapshot(source_uuid) :: {:ok, snapshot} | {:error, :snapshot_not_found}

  @doc """
  Record a snapshot of the data and metadata for a given source
  """
  @callback record_snapshot(snapshot) :: :ok | {:error, reason}

  @doc """
  Delete a previously recorded snapshop for a given source
  """
  @callback delete_snapshot(source_uuid) :: :ok | {:error, reason}

  @doc """
  Append one or more events to a stream atomically.
  """
  @spec append_to_stream(stream_uuid, expected_version :: non_neg_integer, events :: list(EventData.t)) :: {:ok, stream_version} | {:error, :wrong_expected_version} | {:error, reason}
  def append_to_stream(stream_uuid, expected_version, events) do
    event_store_adapter().append_to_stream(stream_uuid, expected_version, events)
  end

  @doc """
  Streams events from the given stream, in the order in which they were
  originally written.
  """
  @spec stream_forward(stream_uuid, start_version :: non_neg_integer, read_batch_size :: non_neg_integer) :: Enumerable.t | {:error, :stream_not_found} | {:error, reason}
  def stream_forward(stream_uuid, start_version \\ 0, read_batch_size \\ 1_000)
  def stream_forward(stream_uuid, start_version, read_batch_size) do
    event_store_adapter().stream_forward(stream_uuid, start_version, read_batch_size)
  end

  @doc """
  Create a transient subscription to a single event stream.
  """
  @spec subscribe(stream_uuid) :: :ok | {:error, reason}
  def subscribe(stream_uuid) do
    event_store_adapter().subscribe(stream_uuid)
  end

  @doc """
  Create a persistent subscription to all event streams.
  """
  @spec subscribe_to_all_streams(subscription_name, subscriber :: pid, start_from) :: {:ok, subscription :: pid}
    | {:error, :subscription_already_exists}
    | {:error, reason}
  def subscribe_to_all_streams(subscription_name, subscriber, start_from) do
    event_store_adapter().subscribe_to_all_streams(subscription_name, subscriber, start_from)
  end

  @doc """
  Acknowledge receipt and successful processing of the given event received from
  a subscription to an event stream.
  """
  @spec ack_event(pid, RecordedEvent.t) :: :ok
  def ack_event(pid, event) do
    event_store_adapter().ack_event(pid, event)
  end

  @doc """
  Unsubscribe an existing subscriber from all event notifications.
  """
  @spec unsubscribe_from_all_streams(subscription_name) :: :ok
  def unsubscribe_from_all_streams(subscription_name) do
    event_store_adapter().unsubscribe_from_all_streams(subscription_name)
  end

  @doc """
  Read a snapshot, if available, for a given source.
  """
  @spec read_snapshot(source_uuid) :: {:ok, snapshot} | {:error, :snapshot_not_found}
  def read_snapshot(source_uuid) do
    event_store_adapter().read_snapshot(source_uuid)
  end

  @doc """
  Record a snapshot of the data and metadata for a given source
  """
  @spec record_snapshot(snapshot) :: :ok | {:error, reason}
  def record_snapshot(snapshot) do
    event_store_adapter().record_snapshot(snapshot)
  end

  @doc """
  Delete a previously recorded snapshop for a given source
  """
  @spec delete_snapshot(source_uuid) :: :ok | {:error, reason}
  def delete_snapshot(source_uuid) do
    event_store_adapter().delete_snapshot(source_uuid)
  end

  @doc """
  Get the configured event store adapter
  """
  def event_store_adapter do
    Application.get_env(:commanded, :event_store_adapter) ||
      raise ArgumentError, "Commanded expects `:event_store_adapter` to be configured in environment"
  end
end
