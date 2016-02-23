defmodule EventStore.EventStream do
  def append(storage, stream_uuid, expected_version, events) do
    {:error, "not yet implemented"}
  end

  def read(storage, stream_uuid) do
    {:error, "not yet implemented"}
  end
  
  def read(storage, stream_uuid, limit) do
    {:error, "not yet implemented"}
  end

  def read(storage, tream_uuid, from_version, limit) do
    {:error, "not yet implemented"}
  end
end