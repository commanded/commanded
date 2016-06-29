defmodule EventStore.Writer do
  @moduledoc """
  Single process writer to assign a monotonically increasing id and persist events to the store
  """

  use GenServer
  require Logger

  alias EventStore.Writer
  alias EventStore.Storage.{Appender,QueryLatestEventId}

  defstruct conn: nil, next_event_id: 0

  def start_link do
    GenServer.start_link(__MODULE__, %Writer{}, name: __MODULE__)
  end

  def init(%Writer{} = state) do
    storage_config = Application.get_env(:eventstore, EventStore.Storage)

    {:ok, conn} = Postgrex.start_link(storage_config)

    GenServer.cast(self, {:latest_event_id})

    {:ok, %Writer{conn: conn}}
  end

  @doc """
  Append the given list of events to the stream
  """
  def append_to_stream(stream_id, events) do
    GenServer.call(__MODULE__, {:append_to_stream, stream_id, events})
  end

  def handle_call({:append_to_stream, stream_id, events}, _from, %Writer{} = state) do
    reply = {:ok, []}
    {:reply, reply, state}
  end

  def handle_cast({:latest_event_id}, %Writer{conn: conn} = state) do
    {:ok, event_id} = QueryLatestEventId.execute(conn)

    {:noreply, %Writer{state | next_event_id: event_id + 1}}
  end
end
