defmodule EventStore.Streams.Supervisor do
  @moduledoc """
  Streams provides access to a stream process by its stream uuid
  """

  use Supervisor
  use EventStore.Registration

  require Logger

  alias EventStore.Streams.Stream

  def start_link(serializer) do
    Supervisor.start_link(__MODULE__, serializer, name: __MODULE__)
  end

  @doc """
  Open a stream, or return the pid of an already opened stream process
  """
  @spec open_stream(String.t) :: {:ok, pid} | {:error, term()}
  def open_stream(stream_uuid) do
    stream_name = Stream.name(stream_uuid)

    case @registry.whereis_name(stream_name) do
      :undefined ->
        case @registry.register_name(stream_name, Supervisor, :start_child, [__MODULE__, [stream_uuid]]) do
          {:ok, stream} -> {:ok, stream}
          {:error, {:already_started, stream}} -> {:ok, stream}
          {:error, _reason} = reply -> reply
        end

      stream ->
        {:ok, stream}
    end
  end

  def close_stream(stream_uuid), do: Stream.close(stream_uuid)

  @doc false
  def init(serializer) do
    children = [
      worker(Stream, [serializer], restart: :temporary)
    ]

    supervise(children, strategy: :simple_one_for_one)
  end
end
