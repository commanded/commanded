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

  def open_stream(stream_uuid) do
    case @registry.register_name(stream_uuid, Supervisor, :start_child, [__MODULE__, [stream_uuid]]) do
      {:ok, stream} -> {:ok, stream}
      {:error, {:already_started, stream}} -> {:ok, stream}
    end
  end

  def close_stream(stream_uuid) do
    case @registry.whereis_name(stream_uuid) do
      :undefined -> :ok
      stream -> Supervisor.terminate_child(__MODULE__, stream)
    end
  end

  @doc false
  def init(serializer) do
    children = [
      worker(Stream, [serializer], restart: :temporary)
    ]

    supervise(children, strategy: :simple_one_for_one)
  end
end
