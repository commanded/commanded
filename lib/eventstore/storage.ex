defmodule EventStore.Storage do
  @moduledoc """
  Storage of events to a PostgreSQL database
  """

  use GenServer
  require Logger

  alias EventStore.Storage
  alias EventStore.Storage.Stream
  alias EventStore.Storage.Subscription

  def start_link do
    config = Application.get_env(:eventstore, Storage)
    GenServer.start_link(__MODULE__, config)
  end

  @doc """
  Initialise the PostgreSQL database by creating the tables and indexs
  """
  def initialize_store!(storage) do
    GenServer.call(storage, :initialize_store)
  end

  @doc """
  Reset the PostgreSQL database by deleting all rows
  """
  def reset!(storage) do
    GenServer.call(storage, :reset_store)
  end

  def append_to_stream(storage, stream_uuid, expected_version, events) do
    GenServer.call(storage, {:append_to_stream, stream_uuid, expected_version, events})
  end

  def read_stream_forward(storage, stream_uuid, start_version, count \\ nil) do
    GenServer.call(storage, {:read_stream_forward, stream_uuid, start_version, count})
  end

  @doc """
  Create, or locate an existing, persistent subscription to a stream using a unique name
  """
  def subscribe_to_stream(storage, stream_uuid, subscription_name) do
    GenServer.call(storage, {:subscribe_to_stream, stream_uuid, subscription_name})
  end

  @doc """
  Acknowledge receipt of an event by id, for a single subscription
  """
  def ack_last_seen_event(storage, stream_uuid, subscription_name, last_seen_event_id) when is_number(last_seen_event_id) do
    GenServer.call(storage, {:ack_last_seen_event, stream_uuid, subscription_name, last_seen_event_id})
  end

  @doc """
  Unsubscribe from an existing named subscription to a stream
  """
  def unsubscribe_from_stream(storage, stream_uuid, subscription_name) do
    GenServer.call(storage, {:unsubscribe_from_stream, stream_uuid, subscription_name})
  end

  @doc """
  Get all known subscriptions, to any stream
  """
  def subscriptions(storage) do
    GenServer.call(storage, {:subscriptions})
  end

  def init(config) do
    Postgrex.start_link(config)
  end

  def handle_call(:initialize_store, _from, conn) do
    Storage.Initializer.run!(conn)
    {:reply, :ok, conn}
  end

  def handle_call(:reset_store, _from, conn) do
    Storage.Initializer.reset!(conn)
    {:reply, :ok, conn}
  end

  def handle_call({:append_to_stream, stream_uuid, expected_version, events}, _from, conn) do
    reply = Stream.append_to_stream(conn, stream_uuid, expected_version, events)
    {:reply, reply, conn}
  end

  def handle_call({:read_stream_forward, stream_uuid, start_version, count}, _from, conn) do
    reply = Stream.read_stream_forward(conn, stream_uuid, start_version, count)
    {:reply, reply, conn}
  end

  def handle_call({:subscribe_to_stream, stream_uuid, subscription_name}, _from, conn) do
    reply = Subscription.subscribe_to_stream(conn, stream_uuid, subscription_name)
    {:reply, reply, conn}
  end

  def handle_call({:unsubscribe_from_stream, stream_uuid, subscription_name}, _from, conn) do
    reply = Subscription.unsubscribe_from_stream(conn, stream_uuid, subscription_name)
    {:reply, reply, conn}
  end

  def handle_call({:ack_last_seen_event, stream_uuid, subscription_name, last_seen_event_id}, _from, conn) do
    reply = Subscription.ack_last_seen_event(conn, stream_uuid, subscription_name, last_seen_event_id)
    {:reply, reply, conn}
  end

  def handle_call({:subscriptions}, _from, conn) do
    reply = Subscription.subscriptions(conn)
    {:reply, reply, conn}
  end
end
