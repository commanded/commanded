defmodule EventStore.Storage.PoolSupervisor do
  use Supervisor

  alias EventStore.Config

  @storage_pool_name :event_store_storage_pool

  def start_link do
    Supervisor.start_link(__MODULE__, nil)
  end

  def init(_) do
    storage_pool_config = [
      {:name, {:local, @storage_pool_name}},
      {:worker_module, Postgrex},
      {:size, 10},
      {:max_overflow, 5}
    ]

    storage_config = Config.parse Application.get_env(:eventstore, EventStore.Storage)

    children = [
      :poolboy.child_spec(@storage_pool_name, storage_pool_config, storage_config)
    ]

    supervise(children, strategy: :one_for_one)
  end

end
