defmodule EventStore.Streams.Supervisor do
  @moduledoc """
  Streams supervisor provides access to a single stream process per logical stream by its stream uuid
  """

  use Supervisor

  require Logger

  alias EventStore.Registration
  alias EventStore.Streams.Stream

  def start_link(serializer) do
    Supervisor.start_link(__MODULE__, serializer, name: __MODULE__)
  end

  @doc """
  Open a stream by starting a `Stream` process, or return the pid of an already started process
  """
  @spec open_stream(String.t) :: {:ok, pid} | {:error, term()}
  def open_stream(stream_uuid) do
    name = Stream.name(stream_uuid)

    case Registration.start_child(name, __MODULE__, [stream_uuid]) do
      {:ok, stream} -> {:ok, stream}
      {:ok, stream, _info} -> {:ok, stream}
      {:error, {:already_started, stream}} -> {:ok, stream}
      reply -> reply
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
