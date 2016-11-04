defmodule EventStore do
  @moduledoc """
  EventStore client API to read & write events to a logical event stream and subscribe to event notifications

  ## Example usage

      # ensure the event store application has been started
      Application.ensure_all_started(:eventstore)

      # append events to a stream
      :ok = EventStore.append_to_stream(stream_uuid, expected_version, events)

      # read all events from a stream, starting at the beginning
      {:ok, recorded_events} = EventStore.read_stream_forward(stream_uuid)
  """

  alias EventStore.Snapshots.{SnapshotData,Snapshotter}
  alias EventStore.{EventData,RecordedEvent,Streams,Subscriptions}
  alias EventStore.Streams.{AllStream,Stream}

  @all_stream "$all"

  @doc """
  Append one or more events to a stream atomically. Returns `:ok` on success.

    - `stream_uuid` is used to uniquely identify a stream.

    - `expected_version` is used for optimistic concurrency.
      Specify 0 for the creation of a new stream. An `{:error, wrong_expected_version}` response will be returned if the stream already exists.
      Any positive number will be used to ensure you can only append to the stream if it is at exactly that version.

    - `events` is a list of `%EventStore.EventData{}` structs.
  """
  @spec append_to_stream(String.t, non_neg_integer, list(EventData.t)) :: :ok | {:error, reason :: term}
  def append_to_stream(stream_uuid, expected_version, events)
  def append_to_stream(@all_stream, _expected_version, _events), do: {:error, :cannot_append_to_all_stream}
  def append_to_stream(stream_uuid, expected_version, events) do
    {:ok, stream} = Streams.open_stream(stream_uuid)

    Stream.append_to_stream(stream, expected_version, events)
  end

  @doc """
  Reads the requested number of events from the given stream, in the order in which they were originally written.

    - `stream_uuid` is used to uniquely identify a stream.

    - `start_version` optionally, the version number of the first event to read.
      Defaults to the beginning of the stream if not set.

    - `count` optionally, the maximum number of events to read.
      If not set it will be limited to returning 1,000 events from the stream.
  """
  @spec read_stream_forward(String.t) :: {:ok, list(RecordedEvent.t)} | {:error, reason :: term}
  @spec read_stream_forward(String.t, non_neg_integer) :: {:ok, list(RecordedEvent.t)} | {:error, reason :: term}
  @spec read_stream_forward(String.t, non_neg_integer, non_neg_integer) :: {:ok, list(RecordedEvent.t)} | {:error, reason :: term}
  def read_stream_forward(stream_uuid, start_version \\ 0, count \\ 1_000) do
    {:ok, stream} = Streams.open_stream(stream_uuid)

    Stream.read_stream_forward(stream, start_version, count)
  end

  @doc """
  Reads the requested number of events from all streams, in the order in which they were originally written.

    - `start_event_id` optionally, the id of the first event to read.
      Defaults to the beginning of the stream if not set.

    - `count` optionally, the maximum number of events to read.
    If not set it will be limited to returning 1,000 events from all streams.
  """
  @spec read_all_streams_forward() :: {:ok, list(RecordedEvent.t)} | {:error, reason :: term}
  @spec read_all_streams_forward(non_neg_integer) :: {:ok, list(RecordedEvent.t)} | {:error, reason :: term}
  @spec read_all_streams_forward(non_neg_integer, non_neg_integer) :: {:ok, list(RecordedEvent.t)} | {:error, reason :: term}
  def read_all_streams_forward(start_event_id \\ 0, count \\ 1_000) do
    AllStream.read_stream_forward(start_event_id, count)
  end

  @doc """
  Subscriber will be notified of each batch of events persisted to a single stream.

    - `stream_uuid` is the stream to subscribe to.
      Use the `$all` identifier to subscribe to events from all streams.

    - `subscription_name` is used to uniquely identify the subscription.

    - `subscriber` is a process that will be sent `{:events, events, subscription}` notification messages.

  Returns `{:ok, subscription}` when subscription succeeds.
  """
  @spec subscribe_to_stream(String.t, String.t, pid) :: {:ok, subscription :: pid}
    | {:error, :subscription_already_exists}
    | {:error, reason :: term}
  def subscribe_to_stream(stream_uuid, subscription_name, subscriber) do
    {:ok, stream} = Streams.open_stream(stream_uuid)

    Stream.subscribe_to_stream(stream, subscription_name, subscriber)
  end

  @doc """
  Subscriber will be notified of every event persisted to any stream.

    - `subscription_name` is used to uniquely identify the subscription.

    - `subscriber` is a process that will be sent `{:events, events, subscription}` notification messages.

  Returns `{:ok, subscription}` when subscription succeeds.
  """
  @spec subscribe_to_all_streams(String.t, pid) :: {:ok, subscription :: pid}
    | {:error, :subscription_already_exists}
    | {:error, reason :: term}
  def subscribe_to_all_streams(subscription_name, subscriber) do
    AllStream.subscribe_to_stream(subscription_name, subscriber)
  end

  @doc """
  Unsubscribe an existing subscriber from event notifications.

    - `stream_uuid` is the stream to unsubscribe from.

    - `subscription_name` is used to identify the existing subscription to remove.

  Returns `:ok` on success.
  """
  @spec unsubscribe_from_stream(String.t, String.t) :: :ok
  def unsubscribe_from_stream(stream_uuid, subscription_name) do
    Subscriptions.unsubscribe_from_stream(stream_uuid, subscription_name)
  end

  @doc """
  Unsubscribe an existing subscriber from all event notifications.

    - `subscription_name` is used to identify the existing subscription to remove.

  Returns `:ok` on success.
  """
  @spec unsubscribe_from_all_streams(String.t) :: :ok
  def unsubscribe_from_all_streams(subscription_name) do
    Subscriptions.unsubscribe_from_stream(@all_stream, subscription_name)
  end

  @doc """
  Read a snapshot, if available, for a given source.

  Returns `{:ok, %EventStore.Snapshots.SnapshotData{}}` on success, or `{:error, :snapshot_not_found}` when unavailable.
  """
  @spec read_snapshot(String.t) :: {:ok, SnapshotData.t} | {:error, :snapshot_not_found}
  def read_snapshot(source_uuid) do
    Snapshotter.read_snapshot(source_uuid)
  end

  @doc """
  Record a snapshot of the data and metadata for a given source

  Returns `:ok` on success
  """
  @spec record_snapshot(SnapshotData.t) :: :ok | {:error, reason :: term}
  def record_snapshot(%SnapshotData{} = snapshot) do
    Snapshotter.record_snapshot(snapshot)
  end

  @doc """
  Record a snapshot of the data and metadata for a given source

  - `timeout` is an integer greater than zero which specifies how many milliseconds to wait for a reply, or the atom :infinity to wait indefinitely. The default value is 5000. If no reply is received within the specified time, the function call fails and the caller exits.
  
  Returns `:ok` on success
  """
  @spec record_snapshot(SnapshotData.t, timeout :: integer) :: :ok | {:error, reason :: term}
  def record_snapshot(%SnapshotData{} = snapshot, timeout) do
    Snapshotter.record_snapshot(snapshot, timeout)
  end
end
