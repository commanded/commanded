defmodule EventStore.Streams.Stream do
  @moduledoc """
  An event stream
  """

  use GenServer
  require Logger

  alias EventStore.Streams.Stream

  defstruct storage: nil, stream_uuid: nil, stream_id: nil, latest_version: 0

  def start_link(storage, stream_uuid) do
    GenServer.start_link(__MODULE__, %Stream{
      storage: storage,
      stream_uuid: stream_uuid
    })
  end

  def append_to_stream(stream, expected_version, events) do
    GenServer.call(stream, {:append_to_stream, expected_version, events})
  end

  def init(%Stream{storage: storage, stream_uuid: stream_uuid} = state) do
    # TODO: Lookup latest version
    {:ok, state}
  end

  def handle_call({:append_to_stream, expected_version, events}, _from, %Stream{} = state) do
    # TODO: Verify latest_version == expected_version
    {:reply, {:ok, events}, state}
  end
end
