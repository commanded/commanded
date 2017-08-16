defmodule EventStore.Registration.LocalRegistry.Supervisor do
  use Supervisor

  def start_link(_) do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_) do
    children = [
      supervisor(Registry, [:unique, EventStore.Registration.LocalRegistry], id: :event_store_local_registry),
    ]

    supervise(children, strategy: :one_for_one)
  end
end
