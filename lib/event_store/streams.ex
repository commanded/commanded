defmodule EventStore.Streams do
  @moduledoc """
  Streams provides access to a stream process by its stream uuid
  """

  use GenServer
  require Logger

  alias EventStore.Streams
  alias EventStore.Streams.{Stream,Supervisor}

  defstruct streams: %{}, supervisor: nil

  def start_link do
    GenServer.start_link(__MODULE__, %Streams{}, name: __MODULE__)
  end

  def open_stream(stream_uuid) do
    GenServer.call(__MODULE__, {:open_stream, stream_uuid})
  end

  def init(%Streams{} = state) do
    {:ok, supervisor} = Streams.Supervisor.start_link

    state = %Streams{state | supervisor: supervisor}

    {:ok, state}
  end

  def handle_call({:open_stream, stream_uuid}, _from, %Streams{streams: streams, supervisor: supervisor} = state) do
    stream = case Map.get(streams, stream_uuid) do
      nil -> start_stream(supervisor, stream_uuid)
      stream -> stream
    end

    state = %Streams{state | streams: Map.put(streams, stream_uuid, stream)}
    {:reply, {:ok, stream}, state}
  end

  def handle_info({:DOWN, ref, :process, pid, reason}, %Streams{streams: streams} = state) do
    Logger.warn "stream down due to: #{reason}"

    state = %Streams{state | streams: remove_stream(streams, pid)}
    {:noreply, state}
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
