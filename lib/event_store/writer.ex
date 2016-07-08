defmodule EventStore.Writer do
  @moduledoc """
  Single process writer to assign a monotonically increasing id and persist events to the store
  """

  use GenServer
  require Logger

  alias EventStore.{EventData,Subscriptions,RecordedEvent,Writer}
  alias EventStore.Storage.{Appender,QueryLatestEventId}

  defstruct conn: nil, next_event_id: 1

  def start_link do
    GenServer.start_link(__MODULE__, %Writer{}, name: __MODULE__)
  end

  def init(%Writer{} = state) do
    storage_config = Application.get_env(:eventstore, EventStore.Storage)

    {:ok, conn} = Postgrex.start_link(storage_config)

    GenServer.cast(self, {:latest_event_id})

    {:ok, %Writer{state | conn: conn}}
  end

  @doc """
  Append the given list of events to the stream
  """
  def append_to_stream(events, stream_uuid, stream_id, stream_version) do
    GenServer.call(__MODULE__, {:append_to_stream, events, stream_uuid, stream_id, stream_version})
  end

  def handle_call({:append_to_stream, events, stream_uuid, stream_id, stream_version}, _from, %Writer{conn: conn, next_event_id: next_event_id} = state) do
    persisted_events =
      events
      |> prepare_events(stream_id, stream_version, next_event_id)
      |> append_events(conn, stream_id)
      |> publish_events(stream_uuid)

    reply = {:ok, persisted_events}
    state = %Writer{state | next_event_id: next_event_id + length(persisted_events)}

    {:reply, reply, state}
  end

  def handle_cast({:latest_event_id}, %Writer{conn: conn} = state) do
    {:ok, last_event_id} = QueryLatestEventId.execute(conn)

    {:noreply, %Writer{state | next_event_id: last_event_id + 1}}
  end

  defp prepare_events(events, stream_id, stream_version, next_event_id) do
    initial_stream_version = stream_version + 1

    events
    |> Enum.map(&map_to_recorded_event(&1))
    |> Enum.with_index(0)
    |> Enum.map(fn {recorded_event, index} ->
      %RecordedEvent{recorded_event |
        event_id: next_event_id + index,
        stream_id: stream_id,
        stream_version: initial_stream_version + index,
      }
    end)
  end

  defp map_to_recorded_event(%EventData{correlation_id: correlation_id, event_type: event_type, headers: headers, payload: payload}) do
    %RecordedEvent{
      correlation_id: correlation_id,
      event_type: event_type,
      headers: headers,
      payload: payload
    }
  end

  defp append_events(recorded_events, conn, stream_id) do
    {:ok, persisted_events} = Appender.append(conn, stream_id, recorded_events)
    persisted_events
  end

  defp publish_events(persisted_events, stream_uuid) do
    :ok = Subscriptions.notify_events(stream_uuid, persisted_events)
    persisted_events
  end
end
