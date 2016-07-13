defmodule EventStore.Supervisor do
  use Supervisor

  @default_serializer EventStore.TermSerializer

  def start_link do
    config = Application.get_env(:eventstore, EventStore.Storage)

    Supervisor.start_link(__MODULE__, config)
  end

  def init(config) do
    serializer = config[:serializer] || @default_serializer
IO.puts "serializer"
IO.inspect serializer

    children = [
      supervisor(EventStore.Storage.PoolSupervisor, []),
      worker(EventStore.Streams, [serializer]),
      worker(EventStore.Subscriptions, []),
      worker(EventStore.Writer, [])
    ]

    supervise(children, strategy: :one_for_one)
  end
end
