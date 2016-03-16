defmodule EventStore.Streams do
  @moduledoc """
  Streams provides access to a stream process by its stream uuid
  """

  use GenServer
  require Logger

  alias EventStore.Storage
  alias EventStore.Streams
  alias EventStore.Streams.{Stream,Supervisor}

  defstruct streams: %{}, storage: nil, supervisor: nil

  def start_link(storage) do
    GenServer.start_link(__MODULE__, %Streams{
      streams: %{},
      storage: storage
    })
  end

  def open_stream(streams, stream_uuid) do
    GenServer.call(streams, {:open_stream, stream_uuid})
  end

  def init(%Streams{storage: storage} = state) do
    {:ok, supervisor} = Streams.Supervisor.start_link(storage)

    state = %Streams{state | supervisor: supervisor}

    {:ok, state}
  end

  def handle_call({:open_stream, stream_uuid}, _from, %Streams{streams: streams, supervisor: supervisor} = state) do
    stream = case Map.get(streams, stream_uuid) do
      nil -> start_stream(supervisor, stream_uuid)
      stream -> stream
    end

    {:reply, {:ok, stream}, %Streams{state | streams: Map.put(streams, stream_uuid, stream)}}
  end

  def handle_info({:DOWN, ref, :process, pid, reason}, %Streams{streams: streams} = state) do
    Logger.warn "stream down due to: #{reason}"
    {:noreply, %Streams{state | streams: remove_stream(streams, pid)}}
  end

  defp start_stream(supervisor, stream_uuid) do
    {:ok, stream} = Streams.Supervisor.start_stream(supervisor, stream_uuid)
    Process.monitor(stream)
    stream
  end

  defp remove_stream(streams, pid) do
    Enum.reduce(streams, streams, fn
      ({stream_uuid, stream_pid}, acc) when stream_pid == pid -> Map.delete(acc, stream_uuid)
      (_, acc) -> acc
    end)
  end
end
