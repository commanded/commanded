defmodule EventStore.Streams.Supervisor do
  @moduledoc """
  Supervise zero, one or more event streams
  """

  use Supervisor

  def start_link do
    Supervisor.start_link(__MODULE__, nil)
  end

  def start_stream(supervisor, stream_uuid) do
    Supervisor.start_child(supervisor, [stream_uuid])
  end

  def init(_) do
    children = [
      worker(EventStore.Streams.Stream, [], restart: :temporary),
    ]

    supervise(children, strategy: :simple_one_for_one)
  end
end
