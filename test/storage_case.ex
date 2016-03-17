defmodule EventStore.StorageCase do
  use ExUnit.CaseTemplate

  alias EventStore.Storage

  setup do
    Storage.reset!
    :ok
  end
end
