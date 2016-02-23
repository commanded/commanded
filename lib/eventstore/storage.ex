defmodule EventStore.Storage do
  use GenServer
  require Logger

  alias EventStore.Storage
  alias EventStore.Storage.Stream

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
end
