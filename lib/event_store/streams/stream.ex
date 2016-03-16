defmodule EventStore.Streams.Stream do
  @moduledoc """
  An event stream
  """

  use GenServer
  require Logger

  alias EventStore.Storage
  alias EventStore.Streams.Stream
  
  defstruct stream_uuid: nil, stream_id: nil, latest_version: nil

  def start_link(stream_uuid) do
    GenServer.start_link(__MODULE__, %Stream{
      stream_uuid: stream_uuid
    })
  end

  def append_to_stream(stream, expected_version, events) do
    GenServer.call(stream, {:append_to_stream, expected_version, events})
  end

  def init(state) do
    {:ok, state}
  end

  def handle_call({:append_to_stream, expected_version, events}, _from, %Stream{stream_uuid: stream_uuid} = state) do
    reply = Storage.append_to_stream(stream_uuid, 0, events)
    {:reply, reply, state}
  end
end
