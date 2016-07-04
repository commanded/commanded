defmodule EventStore.Writer do
  @moduledoc """
  Single process writer to assign a monotonically increasing id and persist events to the store
  """

  use GenServer
  require Logger

  alias EventStore.{EventData,RecordedEvent,Writer}
  alias EventStore.Storage.{Appender,QueryLatestEventId}

  defstruct conn: nil, next_event_id: 1

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
  def append_to_stream(events, stream_id, stream_version) do
    GenServer.call(__MODULE__, {:append_to_stream, events, stream_id, stream_version})
  end

  def handle_call({:append_to_stream, events, stream_id, stream_version}, _from, %Writer{next_event_id: next_event_id} = state) do
    prepared_events = prepare_events(events, stream_id, stream_version)

    reply = {:ok, []}
    state = %Writer{state | next_event_id: next_event_id + length(prepared_events)}

    {:reply, reply, state}
  end

  def handle_cast({:latest_event_id}, %Writer{conn: conn} = state) do
    {:ok, last_event_id} = QueryLatestEventId.execute(conn)

    {:noreply, %Writer{state | next_event_id: last_event_id + 1}}
  end

  defp prepare_events(events, stream_id, stream_version) do
    initial_stream_version = stream_version + 1

    events
    |> Enum.map(&map_to_recorded_event(&1))
    |> Enum.map(&assign_stream_id(&1, stream_id))
    |> Enum.with_index(initial_stream_version)
    |> Enum.map(&assign_stream_version/1)
  end

  defp map_to_recorded_event(%EventData{correlation_id: correlation_id, event_type: event_type, headers: headers, payload: payload}) do
    %RecordedEvent{
      correlation_id: correlation_id,
      event_type: event_type,
      headers: headers,
      payload: payload
    }
  end

  defp assign_stream_id(%RecordedEvent{} = event, stream_id) do
    %RecordedEvent{event | stream_id: stream_id}
  end

  defp assign_stream_version({%RecordedEvent{} = event, stream_version}) do
    %RecordedEvent{event | stream_version: stream_version}
  end
end
