defmodule EventStore.Storage do
  @moduledoc """
  Storage of events to a PostgreSQL database

  Uses a pool of connections to the database.
  This is for increased concurrency and performance, but with an upper limit on concurrent access.
  """

  require Logger

  alias EventStore.Snapshots.SnapshotData
  alias EventStore.Storage
  alias EventStore.Storage.{Reader,Snapshot,Stream,Subscription}

  @event_store :event_store

  @doc """
  Initialise the PostgreSQL database by creating the tables and indexes
  """
  def initialize_store! do
    Storage.Initializer.run!(@event_store)
  end

  @doc """
  Reset the PostgreSQL database by deleting all rows
  """
  def reset! do
    Storage.Initializer.reset!(@event_store)
  end

  @doc """
  Create a new event stream with the given unique identifier
  """
  def create_stream(stream_uuid) do
    Stream.create_stream(@event_store, stream_uuid)
  end

  @doc """
  Read events for the given stream forward from the starting version, use zero for all events for the stream
  """
  def read_stream_forward(stream_id, start_version, count) do
    Reader.read_forward(@event_store, stream_id, start_version, count)
  end

  @doc """
  Read events for all streams forward from the starting event id, use zero for all events for all streams
  """
  def read_all_streams_forward(start_event_id, count) do
    Stream.read_all_streams_forward(@event_store, start_event_id, count)
  end

  @doc """
  Get the id of the last event persisted to storage
  """
  def latest_event_id do
    Stream.latest_event_id(@event_store)
  end

  @doc """
  Get the id and version of the stream with the given uuid
  """
  def stream_info(stream_uuid) do
    Stream.stream_info(@event_store, stream_uuid)
  end

  @doc """
  Get the latest version of events persisted to the given stream
  """
  def latest_stream_version(stream_uuid) do
    Stream.latest_stream_version(@event_store, stream_uuid)
  end

  @doc """
  Create, or locate an existing, persistent subscription to a stream using a unique name and starting position (event id or stream version)
  """
  def subscribe_to_stream(stream_uuid, subscription_name, start_from_event_id \\ nil, start_from_stream_version \\ nil) do
    Subscription.subscribe_to_stream(@event_store, stream_uuid, subscription_name, start_from_event_id, start_from_stream_version)
  end

  @doc """
  Acknowledge receipt of an event by id, for a single subscription
  """
  def ack_last_seen_event(stream_uuid, subscription_name, last_seen_event_id, last_seen_stream_version) do
    Subscription.ack_last_seen_event(@event_store, stream_uuid, subscription_name, last_seen_event_id, last_seen_stream_version)
  end

  @doc """
  Unsubscribe from an existing named subscription to a stream
  """
  def unsubscribe_from_stream(stream_uuid, subscription_name) do
    Subscription.unsubscribe_from_stream(@event_store, stream_uuid, subscription_name)
  end

  @doc """
  Get all known subscriptions, to any stream
  """
  def subscriptions do
    Subscription.subscriptions(@event_store)
  end

  @doc """
  Read a snapshot, if available, for a given source
  """
  def read_snapshot(source_uuid) do
    Snapshot.read_snapshot(@event_store, source_uuid)
  end

  @doc """
  Record a snapshot of the data and metadata for a given source
  """
  def record_snapshot(%SnapshotData{} = snapshot) do
    Snapshot.record_snapshot(@event_store, snapshot)
  end

  @doc """
  Delete an existing snapshot for a given source
  """
  def delete_snapshot(source_uuid) do
    Snapshot.delete_snapshot(@event_store, source_uuid)
  end
end
