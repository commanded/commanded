defmodule EventStore.StorageCase do
  use ExUnit.CaseTemplate

  alias EventStore.Storage

  setup do
    Application.stop(:eventstore)
    reset_storage
    Application.start(:eventstore)
  end

  defp reset_storage do
    storage_config = Application.get_env(:eventstore, EventStore.Storage)

    {:ok, conn} = Postgrex.start_link(storage_config)

    Storage.Initializer.reset!(conn)
  end
end
