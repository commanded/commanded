defmodule EventStore.StorageCase do
  use ExUnit.CaseTemplate

  setup do
    EventStore.StorageInitializer.reset_storage!()
  end
end
