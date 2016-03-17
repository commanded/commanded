defmodule EventStore.StorageCase do
  use ExUnit.CaseTemplate

  alias EventStore.Storage

  setup do
    Application.stop(:eventstore)
    :ok = Application.start(:eventstore)

    Storage.reset!
    :ok
  end
end
