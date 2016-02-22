defmodule EventStore.Storage do
  use GenServer
  require Logger

  alias EventStore.Storage

  def start_link do
    config = Application.get_env(:eventstore, Storage)
    GenServer.start_link(__MODULE__, config)
  end

  def initialize_store!(storage) do
    GenServer.call(storage, :initialize_store)
  end

  def init(config) do
    Postgrex.start_link(config)
  end

  def handle_call(:initialize_store, _from, conn) do
    Logger.info "initialize storage"

    EventStore.Sql.Statements.all 
    |> Enum.each(&(Postgrex.query!(conn, &1, [])))

    Logger.info "storage available"
    
    {:reply, :ok, conn}
  end
end