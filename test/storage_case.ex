defmodule EventStore.StorageCase do
  use ExUnit.CaseTemplate

  alias EventStore.Storage

  @all_stream "$all"

  setup do
    Storage.reset!
    :ok
  end
end
