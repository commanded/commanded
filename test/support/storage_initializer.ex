defmodule EventStore.StorageInitializer do
  alias EventStore.Storage

  def reset_storage! do
    Application.stop(:eventstore)

    storage_config = Application.get_env(:eventstore, EventStore.Storage)

    {:ok, conn} = Postgrex.start_link(storage_config)

    Storage.Initializer.reset!(conn)

    {:ok, _} = Application.ensure_all_started(:eventstore)

    :ok
  end
end
