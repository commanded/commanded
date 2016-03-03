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

  def initialize_store!(storage) do
    GenServer.call(storage, :initialize_store)
  end

  def append_to_stream(storage, stream_uuid, expected_version, events) do
    GenServer.call(storage, {:append_to_stream, stream_uuid, expected_version, events})
  end

  def read_stream_forward(storage, stream_uuid, start_version, count \\ nil) do
    GenServer.call(storage, {:read_stream_forward, stream_uuid, start_version, count})
  end

  def subscribe_to_stream(storage, stream_uuid, subscription_name) do
    GenServer.call(storage, {:subscribe_to_stream, stream_uuid, subscription_name})
  end

  def init(config) do
    Postgrex.start_link(config)
  end

  def handle_call(:initialize_store, _from, conn) do
    Storage.Initializer.run!(conn)
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
end
