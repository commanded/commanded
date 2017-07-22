defmodule EventStore.Streams.Supervisor do
  @moduledoc """
  Streams provides access to a stream process by its stream uuid
  """

  use Supervisor
  require Logger

  alias EventStore.Streams.Stream

  def start_link do
    Supervisor.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def open_stream(stream_uuid) do
    case Supervisor.start_child(__MODULE__, [stream_uuid]) do
      {:ok, stream} -> {:ok, stream}
      {:error, {:already_started, stream}} -> {:ok, stream}
    end
  end

  def close_stream(stream_uuid) do
    case Registry.lookup(EventStore.Streams, stream_uuid) do
      [] -> :ok
      [{stream, _}] -> Supervisor.terminate_child(__MODULE__, stream)
    end
  end

  @doc false
  def init(_) do
    children = [
      worker(Stream, [], restart: :temporary)
    ]

    supervise(children, strategy: :simple_one_for_one)
  end
end
