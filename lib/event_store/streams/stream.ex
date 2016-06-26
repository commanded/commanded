defmodule EventStore.Streams.Stream do
  @moduledoc """
  An event stream
  """

  use GenServer
  require Logger

  alias EventStore.Storage
  alias EventStore.Streams.Stream

  defstruct stream_uuid: nil, stream_id: nil, stream_version: nil

  def start_link(stream_uuid) do
    GenServer.start_link(__MODULE__, %Stream{
      stream_uuid: stream_uuid
    })
  end

  @doc """
  Append the given list of events to the stream, expected version is used for optimistic concurrency

  A stream is a GenServer process, so writes to a single logical stream will always be serialized.
  """
  def append_to_stream(stream, expected_version, events) do
    GenServer.call(stream, {:append_to_stream, expected_version, events})
  end

  def init(state) do
    # fetch stream id and latest version
    {:ok, state}
  end

  def handle_call({:append_to_stream, expected_version, events}, _from, %Stream{stream_uuid: stream_uuid, stream_id: stream_id} = state) do
    {:ok, stream_id, persisted_events} = append_to_storage(expected_version, events, stream_uuid, stream_id)

    state = %Stream{state| stream_id: stream_id}
    reply = {:ok, persisted_events}

    {:reply, reply, state}
  end

  defp append_to_storage(expected_version, events, stream_uuid, stream_id) when expected_version == 0 and is_nil(stream_id) do
    with {:ok, stream_id} <- Storage.create_stream(stream_uuid),
         {:ok, persisted_events} <- Storage.append_to_stream(stream_id, expected_version, events),
    do: {:ok, stream_id, persisted_events}
  end

  defp append_to_storage(expected_version, events, stream_uuid, stream_id) when expected_version > 0 and not is_nil(stream_id) do
    {:ok, persisted_events} = Storage.append_to_stream(stream_id, expected_version, events)
    {:ok, stream_id, persisted_events}
  end

  defp append_to_storage(_expected_version, _events, _stream_uuid, _stream_id) do
    {:error, :wrong_expected_version}
  end
end
