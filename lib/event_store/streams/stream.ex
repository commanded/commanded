defmodule EventStore.Streams.Stream do
  @moduledoc """
  An event stream
  """

  use GenServer
  require Logger

  alias EventStore.{Storage,Writer}
  alias EventStore.Streams.Stream

  defstruct stream_uuid: nil, stream_id: nil, stream_version: 0

  def start_link(stream_uuid) do
    GenServer.start_link(__MODULE__, %Stream{stream_uuid: stream_uuid})
  end

  @doc """
  Append the given list of events to the stream, expected version is used for optimistic concurrency

  Each logical stream is a separate process; writes to a single stream will always be serialized.
  """
  def append_to_stream(stream, expected_version, events) do
    GenServer.call(stream, {:append_to_stream, expected_version, events})
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

  defp append_to_storage(expected_version, events, %Stream{stream_uuid: stream_uuid, stream_id: stream_id, stream_version: stream_version} = state) when expected_version == 0 and is_nil(stream_id) and stream_version == 0 do
    with {:ok, stream_id} <- Storage.create_stream(stream_uuid),
         {:ok, persisted_events} <- Writer.append_to_stream(events, stream_id, stream_version),
    do: {:ok, %Stream{state | stream_id: stream_id}, persisted_events}
  end

  defp append_to_storage(expected_version, events, %Stream{stream_id: stream_id, stream_version: stream_version} = state) when expected_version > 0 and not is_nil(stream_id) and stream_version == expected_version do
    {:ok, persisted_events} = Writer.append_to_stream(events, stream_id, stream_version)
    {:ok, state, persisted_events}
  end

  defp append_to_storage(_expected_version, _events, _stream_uuid, _stream_id) do
    {:error, :wrong_expected_version}
  end
end
