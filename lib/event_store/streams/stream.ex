defmodule EventStore.Streams.Stream do
  @moduledoc """
  An event stream
  """

  use GenServer
  require Logger

  alias EventStore.{EventData,RecordedEvent,Storage,Writer}
  alias EventStore.Streams.Stream

  defstruct stream_uuid: nil, stream_id: nil, stream_version: 0, serializer: nil

  def start_link(serializer, stream_uuid) do
    GenServer.start_link(__MODULE__, %Stream{serializer: serializer, stream_uuid: stream_uuid})
  end

  @doc """
  Append the given list of events to the stream, expected version is used for optimistic concurrency

  Each logical stream is a separate process; writes to a single stream will always be serialized.
  """
  def append_to_stream(stream, expected_version, events) do
    GenServer.call(stream, {:append_to_stream, expected_version, events})
  end

  def read_stream_forward(stream, start_version \\ 0, count \\ nil) do
    GenServer.call(stream, {:read_stream_forward, start_version, count})
  end

  def init(%Stream{stream_uuid: stream_uuid} = state) do
    GenServer.cast(self, {:open_stream, stream_uuid})
    {:ok, state}
  end

  def handle_cast({:open_stream, stream_uuid}, %Stream{} = state) do
    {:ok, stream_id, stream_version} = Storage.stream_info(stream_uuid)

    state = %Stream{state | stream_id: stream_id, stream_version: stream_version}

    {:noreply, state}
  end

  def handle_call({:append_to_stream, expected_version, events}, _from, %Stream{stream_version: stream_version} = state) do
    {:ok, state, persisted_events} = append_to_storage(expected_version, events, state)

    state = %Stream{state | stream_version: stream_version + length(persisted_events)}

    {:reply, {:ok, persisted_events}, state}
  end

  def handle_call({:read_stream_forward, start_version, count}, _from, %Stream{stream_id: stream_id, serializer: serializer} = state) do
    reply = read_storage_forward(stream_id, start_version, count, serializer)

    {:reply, reply, state}
  end

  defp append_to_storage(expected_version, events, %Stream{stream_uuid: stream_uuid, stream_id: stream_id, stream_version: stream_version, serializer: serializer} = state) when expected_version == 0 and is_nil(stream_id) and stream_version == 0 do
    with {:ok, stream_id} <- Storage.create_stream(stream_uuid),
         {:ok, prepared_events} <- prepare_events(events, stream_id, stream_version, serializer),
         {:ok, persisted_events} <- Writer.append_to_stream(prepared_events, stream_id, stream_uuid),
    do: {:ok, %Stream{state | stream_id: stream_id}, persisted_events}
  end

  defp append_to_storage(expected_version, events, %Stream{stream_uuid: stream_uuid, stream_id: stream_id, stream_version: stream_version, serializer: serializer} = state) when expected_version > 0 and not is_nil(stream_id) and stream_version == expected_version do
    {:ok, prepared_events} = prepare_events(events, stream_id, stream_version, serializer)
    {:ok, persisted_events} = Writer.append_to_stream(prepared_events, stream_id, stream_uuid)
    {:ok, state, persisted_events}
  end

  defp append_to_storage(_expected_version, _events, _state) do
    {:error, :wrong_expected_version}
  end

  defp prepare_events(events, stream_id, stream_version, serializer) do
    initial_stream_version = stream_version + 1

    prepared_events =
      events
      |> Enum.map(fn event -> map_to_recorded_event(event, serializer) end)
      |> Enum.with_index(0)
      |> Enum.map(fn {recorded_event, index} ->
        %RecordedEvent{recorded_event |
          stream_id: stream_id,
          stream_version: initial_stream_version + index,
        }
      end)

    {:ok, prepared_events}
  end

  defp map_to_recorded_event(%EventData{correlation_id: correlation_id, event_type: event_type, headers: headers, payload: payload}, serializer) do
    %RecordedEvent{
      correlation_id: correlation_id,
      event_type: event_type,
      headers: serializer.serialize(headers),
      payload: serializer.serialize(payload)
    }
  end

  defp read_storage_forward(stream_id, start_version, count, serializer) when not is_nil(stream_id) do
    {:ok, recorded_events} = Storage.read_stream_forward(stream_id, start_version, count)

    events = Enum.map(recorded_events, fn event -> deserialize_recorded_event(event, serializer) end)

    {:ok, events}
  end

  defp read_storage_forward(_stream_id, _start_version, _count, _serializer) do
    {:error, :stream_not_found}
  end

  defp deserialize_recorded_event(%RecordedEvent{headers: headers, payload: payload, event_type: event_type} = recorded_event, serializer) do
    %RecordedEvent{recorded_event |
      headers: serializer.deserialize(headers, []),
      payload: serializer.deserialize(payload, type: event_type),
    }
  end
end
