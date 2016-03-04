defmodule EventStore.StorageCase do
  use ExUnit.CaseTemplate

  alias EventStore.Storage

  @all_stream "$all"

  setup do
    {:ok, storage} = create_storage
    {:ok, storage: storage}
  end

  defp create_storage do
    {:ok, storage} = reply = Storage.start_link
    :ok = Storage.reset!(storage)
    reply
  end
end
