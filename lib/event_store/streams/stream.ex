defmodule EventStore.Streams.Stream do
  @moduledoc """
  An event stream
  """

  use GenServer

  require Logger

  alias EventStore.{EventData,RecordedEvent,Storage,Subscriptions,Writer}
  alias EventStore.Streams.Stream

  defstruct [
    serializer: nil,
    stream_uuid: nil,
    stream_id: nil,
    stream_version: 0,
  ]

  def start_link(serializer, stream_uuid) do
    name = via_tuple(stream_uuid)

    GenServer.start_link(__MODULE__, %Stream{serializer: serializer, stream_uuid: stream_uuid}, name: name)
  end

  @doc """
  Append a list of events to the stream, expected version is used for optimistic concurrency.

  Each logical stream is a separate process; writes to a single stream will always be serialized.

  Returns `:ok` on success.
  """
  def append_to_stream(stream_uuid, expected_version, events) do
    GenServer.call(via_tuple(stream_uuid), {:append_to_stream, expected_version, events})
  end

  def read_stream_forward(stream_uuid, start_version, count) do
    GenServer.call(via_tuple(stream_uuid), {:read_stream_forward, start_version, count})
  end

  def stream_forward(stream_uuid, start_version, read_batch_size) do
    GenServer.call(via_tuple(stream_uuid), {:stream_forward, start_version, read_batch_size})
  end

  def subscribe_to_stream(stream_uuid, subscription_name, subscriber, opts) do
    GenServer.call(via_tuple(stream_uuid), {:subscribe_to_stream, subscription_name, subscriber, opts})
  end

  def stream_version(stream_uuid) do
    GenServer.call(via_tuple(stream_uuid), {:stream_version})
  end

  def init(%Stream{stream_uuid: stream_uuid} = state) do
    GenServer.cast(self(), {:open_stream, stream_uuid})
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

  def handle_call({:stream_forward, start_version, read_batch_size}, _from, %Stream{stream_id: stream_id, serializer: serializer} = state) do
    reply = stream_storage_forward(stream_id, start_version, read_batch_size, serializer)

    {:reply, reply, state}
  end

  def handle_call({:subscribe_to_stream, subscription_name, subscriber, opts}, _from, %Stream{stream_uuid: stream_uuid} = state) do
    {start_from, opts} = Keyword.pop(opts, :start_from, :origin)

    opts = Keyword.merge([start_from_stream_version: start_from_stream_version(state, start_from)], opts)

    reply = Subscriptions.subscribe_to_stream(stream_uuid, subscription_name, subscriber, opts)

    {:reply, reply, state}
  end

  def handle_call({:stream_version}, _from, %Stream{stream_version: stream_version} = state) do
    {:reply, {:ok, stream_version}, state}
  end

  defp start_from_stream_version(%Stream{}, :origin), do: 0
  defp start_from_stream_version(%Stream{stream_version: stream_version}, :current), do: stream_version
  defp start_from_stream_version(%Stream{}, start_from) when is_integer(start_from), do: start_from

  defp append_to_storage(expected_version, events, %Stream{stream_uuid: stream_uuid, stream_id: stream_id, stream_version: stream_version} = state) when expected_version == 0 and is_nil(stream_id) and stream_version == 0 do
    {:ok, stream_id} = Storage.create_stream(stream_uuid)

    append_to_storage(expected_version, events, %Stream{state | stream_id: stream_id})
  end

  defp append_to_storage(expected_version, events, %Stream{stream_id: stream_id, stream_version: stream_version} = stream)
    when not is_nil(stream_id) and stream_version == expected_version
  do
    reply =
      events
      |> prepare_events(stream)
      |> write_to_stream(stream)

    {reply, stream}
  end

  defp append_to_storage(_expected_version, _events, _state), do: {:error, :wrong_expected_version}

  defp prepare_events(events, %Stream{serializer: serializer, stream_id: stream_id, stream_version: stream_version}) do
    initial_stream_version = stream_version + 1

    events
    |> Enum.map(&map_to_recorded_event(&1, serializer))
    |> Enum.with_index(0)
    |> Enum.map(fn {recorded_event, index} ->
      %RecordedEvent{recorded_event |
        stream_id: stream_id,
        stream_version: initial_stream_version + index
      }
    end)
  end

  defp map_to_recorded_event(%EventData{correlation_id: correlation_id, causation_id: causation_id, event_type: event_type, data: data, metadata: metadata}, serializer) do
    %RecordedEvent{
      correlation_id: correlation_id,
      causation_id: causation_id,
      event_type: event_type,
      data: serializer.serialize(data),
      metadata: serializer.serialize(metadata),
      created_at: utc_now(),
    }
  end

  # Returns the current naive date time in UTC.
  defp utc_now do
    DateTime.utc_now |> DateTime.to_naive
  end

  defp write_to_stream(prepared_events, %Stream{stream_uuid: stream_uuid, serializer: serializer}) do
    Writer.append_to_stream(prepared_events, stream_uuid, serializer)
  end

  defp read_storage_forward(stream_id, start_version, count, serializer) when not is_nil(stream_id) do
    case Storage.read_stream_forward(stream_id, start_version, count) do
      {:ok, recorded_events} -> {:ok, deserialize_recorded_events(recorded_events, serializer)}
      {:error, _reason} = reply -> reply
    end
  end
  defp read_storage_forward(_stream_id, _start_version, _count, _serializer), do: {:error, :stream_not_found}

  defp stream_storage_forward(stream_id, 0, read_batch_size, serializer), do: stream_storage_forward(stream_id, 1, read_batch_size, serializer)
  defp stream_storage_forward(stream_id, start_version, read_batch_size, serializer) when not is_nil(stream_id) do
    Elixir.Stream.resource(
      fn -> start_version end,
      fn next_version ->
        case read_storage_forward(stream_id, next_version, read_batch_size, serializer) do
          {:ok, []} -> {:halt, next_version}
          {:ok, events} -> {events, next_version + length(events)}
        end
      end,
      fn _ -> :ok end
    )
  end
  defp stream_storage_forward(_stream_id, _start_version, _read_batch_size, _serializer), do: {:error, :stream_not_found}

  defp deserialize_recorded_events(recorded_events, serializer) do
    Enum.map(recorded_events, &RecordedEvent.deserialize(&1, serializer))
  end

  defp via_tuple(stream_uuid), do: {:via, Registry, {EventStore.Streams, stream_uuid}}
end
