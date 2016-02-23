defmodule EventStore.Storage do
  use GenServer
  require Logger

  alias EventStore.Sql.Statements
  alias EventStore.Storage

  def start_link do
    config = Application.get_env(:eventstore, Storage)
    GenServer.start_link(__MODULE__, config)
  end

  def initialize_store!(storage) do
    GenServer.call(storage, :initialize_store)
  end

  def append_to_stream(storage, stream_uuid, expected_version, events) when expected_version == 0 do
    GenServer.call(storage, {:create_stream, stream_uuid})
  end

  def append_to_stream(storage, stream_uuid, expected_version, events) do
  end

  def init(config) do
    Postgrex.start_link(config)
  end

  def handle_call(:initialize_store, _from, conn) do
    EventStore.Storage.Initializer.run!(conn)
    {:reply, :ok, conn}
  end

  def handle_call({:create_stream, stream_uuid}, _from, conn) do
    reply = Storage.Stream.create(conn, stream_uuid)
    {:reply, reply, conn}
  end
end
