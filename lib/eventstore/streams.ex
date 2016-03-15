defmodule EventStore.Streams do
  @moduledoc """
  Streams holds state for in-use event streams
  """

  use GenServer
  require Logger

  alias EventStore.Storage
  alias EventStore.Streams
  alias EventStore.Streams.{Stream,Supervisor}

  defstruct streams: %{}, storage: nil, supervisor: nil

  @all_stream "$all"

  def start_link(storage) do
    GenServer.start_link(__MODULE__, %Streams{
      open_streams: %{},
      storage: storage
    })
  end

  def append_to_stream(streams, stream_uuid, expected_version, events) do
    GenServer.call(streams, {:append_to_stream, stream_uuid, expected_version, events})
  end

  def init(%Streams{storage: storage} = state) do
    {:ok, supervisor} = Streams.Supervisor.start_link(storage)

    state = %Streams{state | supervisor: supervisor}

    {:ok, state}
  end

  def handle_call({:append_to_stream, stream_uuid, expected_version, events}, _from, %Streams{streams: streams, supervisor: supervisor} = state) do
    {:ok, stream} = open_stream(state, stream_uuid)
    {:ok, persisted_events} = Stream.append_to_stream(stream, expected_version, events)

    state = %Streams{streams: Map.put(streams, stream)}

    {:reply, {:ok, persisted_events}, state}
  end

  def handle_info({:DOWN, ref, :process, pid, reason}, %Stream{streams: streams} = state) do
    Logger.warn "stream down due to: #{reason}"

    state = close_stream(state, pid)

    {:noreply, state}
  end

  defp open_stream(%Streams{streams: streams} = state, stream_uuid) do
    case Map.get(streams, stream_uuid) do
      nil ->
        {:ok, stream} = Streams.Supervisor.create_stream(supervisor, stream_uuid)
        Process.monitor(stream)
        stream
      stream -> stream
    end
  end

  defp close_stream(%Streams{streams: streams} = state, stream) do
    state
  end
end
