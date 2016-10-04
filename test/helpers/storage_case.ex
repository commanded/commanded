defmodule Commanded.StorageCase do
  use ExUnit.CaseTemplate

  setup do
    Application.stop(:commanded)
    EventStore.Storage.reset!
    Application.start(:commanded)
  end
end
