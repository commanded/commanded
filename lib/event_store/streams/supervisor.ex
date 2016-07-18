defmodule EventStore.Streams.Supervisor do
  @moduledoc """
  Supervise zero, one or more event streams
  """

  use Supervisor

  def start_link(serializer) do
    Supervisor.start_link(__MODULE__, serializer)
  end

  def start_stream(supervisor, stream_uuid) do
    Supervisor.start_child(supervisor, [stream_uuid])
  end

  def init(serializer) do
    children = [
      worker(EventStore.Streams.Stream, [serializer], restart: :temporary),
    ]

    supervise(children, strategy: :simple_one_for_one)
  end
end
