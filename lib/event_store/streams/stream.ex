defmodule EventStore.Streams.Stream do
  @moduledoc """
  An event stream
  """

  use GenServer
  require Logger

  alias EventStore.{EventData,RecordedEvent,Storage,Subscriptions,Writer}
  alias EventStore.Streams.Stream

  defstruct stream_uuid: nil, stream_id: nil, stream_version: 0, serializer: nil

  def start_link(serializer, stream_uuid) do
    GenServer.start_link(__MODULE__, %Stream{serializer: serializer, stream_uuid: stream_uuid})
  end

  @doc """
  Append the given list of events to the stream, expected version is used for optimistic concurrency.

  Each logical stream is a separate process; writes to a single stream will always be serialized.

  Returns `:ok` on success
  """
  def append_to_stream(stream, expected_version, events) do
    GenServer.call(stream, {:append_to_stream, expected_version, events})
  end

  def read_stream_forward(stream, start_version, count) do
    GenServer.call(stream, {:read_stream_forward, start_version, count})
  end

  def subscribe_to_stream(stream, subscription_name, subscriber) do
    GenServer.call(stream, {:subscribe_to_stream, subscription_name, subscriber})
  end

  def stream_version(stream) do
    GenServer.call(stream, {:stream_version})
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
    {reply, state} = case append_to_storage(expected_version, events, state) do
      {:ok, state} -> {:ok, %Stream{state | stream_version: stream_version + length(events)}}
      {:error, :wrong_expected_version} = reply -> {reply, state}
    end

    {:reply, reply, state}
  end

  def handle_call({:read_stream_forward, start_version, count}, _from, %Stream{stream_id: stream_id, serializer: serializer} = state) do
    reply = read_storage_forward(stream_id, start_version, count, serializer)

    {:reply, reply, state}
  end

  def handle_call({:subscribe_to_stream, subscription_name, subscriber}, _from, %Stream{stream_uuid: stream_uuid} = state) do
    reply = Subscriptions.subscribe_to_stream(stream_uuid, self, subscription_name, subscriber)

    {:reply, reply, state}
  end

  def handle_call({:stream_version}, _from, %Stream{stream_version: stream_version} = state) do
    {:reply, {:ok, stream_version}, state}
  end

  defp append_to_storage(expected_version, events, %Stream{stream_uuid: stream_uuid, stream_id: stream_id, stream_version: stream_version} = state) when expected_version == 0 and is_nil(stream_id) and stream_version == 0 do
    {:ok, stream_id} = Storage.create_stream(stream_uuid)

    append_to_storage(expected_version, events, %Stream{state | stream_id: stream_id})
  end

  defp append_to_storage(expected_version, events, %Stream{stream_uuid: stream_uuid, stream_id: stream_id, stream_version: stream_version, serializer: serializer} = state) when not is_nil(stream_id) and stream_version == expected_version do
    reply =
      events
      |> prepare_events(stream_id, stream_version, serializer)
      |> write_to_stream(stream_id, stream_uuid)

    {reply, state}
  end

  defp append_to_storage(_expected_version, _events, _state), do: {:error, :wrong_expected_version}

  defp prepare_events(events, stream_id, stream_version, serializer) do
    initial_stream_version = stream_version + 1

    events
    |> Enum.map(fn event -> map_to_recorded_event(event, serializer) end)
    |> Enum.with_index(0)
    |> Enum.map(fn {recorded_event, index} ->
      %RecordedEvent{recorded_event |
        stream_id: stream_id,
        stream_version: initial_stream_version + index
      }
    end)
  end

  defp map_to_recorded_event(%EventData{correlation_id: correlation_id, event_type: event_type, data: data, metadata: metadata}, serializer) do
    %RecordedEvent{
      correlation_id: correlation_id,
      event_type: event_type,
      data: serializer.serialize(data),
      metadata: serializer.serialize(metadata)
    }
  end

  defp write_to_stream(prepared_events, stream_id, stream_uuid) do
    Writer.append_to_stream(prepared_events, stream_id, stream_uuid)
  end

  defp read_storage_forward(stream_id, start_version, count, serializer) when not is_nil(stream_id) do
    case Storage.read_stream_forward(stream_id, start_version, count) do
      {:ok, recorded_events} -> {:ok, deserialize_recorded_events(recorded_events, serializer)}
      {:error, _reason} = reply -> reply
    end
  end
  defp read_storage_forward(_stream_id, _start_version, _count, _serializer), do: {:error, :stream_not_found}

  defp deserialize_recorded_events(recorded_events, serializer) do
    Enum.map(recorded_events, &deserialize_recorded_event(&1, serializer))
  end

  defp deserialize_recorded_event(%RecordedEvent{data: data, metadata: metadata, event_type: event_type} = recorded_event, serializer) do
    %RecordedEvent{recorded_event |
      data: serializer.deserialize(data, type: event_type),
      metadata: serializer.deserialize(metadata, [])
    }
  end
end
