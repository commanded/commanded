defmodule EventStore.Storage do
  @moduledoc """
  Storage of events to a PostgreSQL database

  Uses a pool of connections to the database.
  This is for increased concurrency and performance, but with an upper limit on concurrent access.
  """

  require Logger

  alias EventStore.Storage
  alias EventStore.Storage.Stream
  alias EventStore.Storage.Subscription

  @storage_pool_name :event_store_storage_pool

  @doc """
  Initialise the PostgreSQL database by creating the tables and indexes
  """
  def initialize_store! do
    storage_pool(fn conn ->
      Storage.Initializer.run!(conn)
    end)
    :ok
  end

  @doc """
  Reset the PostgreSQL database by deleting all rows
  """
  def reset! do
    storage_pool(fn conn ->
      Storage.Initializer.reset!(conn)
    end)
  end

  @doc """
  Append the given list of events to the stream, expected version is used for optimistic concurrency
  """
  def append_to_stream(stream_uuid, expected_version, events) do
    storage_pool(fn conn ->
      Stream.append_to_stream(conn, stream_uuid, expected_version, events)
    end)
  end

  @doc """
  Read events for the given stream forward from the starting version, use zero for all events for the stream
  """
  def read_stream_forward(stream_uuid, start_version, count \\ nil) do
    storage_pool(fn conn ->
      Stream.read_stream_forward(conn, stream_uuid, start_version, count)
    end)
  end

  @doc """
  Read events for all streams forward from the starting event id, use zero for all events for all streams
  """
  def read_all_streams_forward(start_event_id \\ 0, count \\ nil) do
    storage_pool(fn conn ->
      Stream.read_all_streams_forward(conn, start_event_id, count)
    end)
  end

  @doc """
  Get the id of the last event persisted to storage
  """
  def latest_event_id do
    storage_pool(fn conn ->
      Stream.latest_event_id(conn)
    end)
  end

  @doc """
  Create, or locate an existing, persistent subscription to a stream using a unique name
  """
  def subscribe_to_stream(stream_uuid, subscription_name) do
    storage_pool(fn conn ->
      Subscription.subscribe_to_stream(conn, stream_uuid, subscription_name)
    end)
  end

  @doc """
  Acknowledge receipt of an event by id, for a single subscription
  """
  def ack_last_seen_event(stream_uuid, subscription_name, last_seen_event_id) when is_number(last_seen_event_id) do
    storage_pool(fn conn ->
      Subscription.ack_last_seen_event(conn, stream_uuid, subscription_name, last_seen_event_id)
    end)
  end

  @doc """
  Unsubscribe from an existing named subscription to a stream
  """
  def unsubscribe_from_stream(stream_uuid, subscription_name) do
    storage_pool(fn conn ->
      Subscription.unsubscribe_from_stream(conn, stream_uuid, subscription_name)
    end)
  end

  @doc """
  Get all known subscriptions, to any stream
  """
  def subscriptions do
    storage_pool(fn conn ->
      Subscription.subscriptions(conn)
    end)
  end

  # Execute the given `transaction` function using a database worker from the pool
  defp storage_pool(transaction) do
    :poolboy.transaction(@storage_pool_name, transaction)
  end
end
