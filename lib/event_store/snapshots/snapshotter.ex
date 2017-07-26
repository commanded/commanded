defmodule EventStore.Snapshots.Snapshotter do
  @moduledoc """
  Record and read snapshots of process state
  """

  alias EventStore.Snapshots.SnapshotData
  alias EventStore.Storage

  @doc """
  Read a snapshot, if available, for a given source
  """
  def read_snapshot(source_uuid, serializer) do
    case Storage.read_snapshot(source_uuid) do
      {:ok, snapshot} -> {:ok, SnapshotData.deserialize(snapshot, serializer)}
      reply -> reply
    end
  end

  @doc """
  Record a snapshot containing data and metadata for a given source

  Returns `:ok` on success
  """
  def record_snapshot(%SnapshotData{} = snapshot, serializer) do
    snapshot
    |> SnapshotData.serialize(serializer)
    |> Storage.record_snapshot()
  end

  @doc """
  Delete a previously recorded snapshot for a given source

  Returns `:ok` on success
  """
  def delete_snapshot(source_uuid), do: Storage.delete_snapshot(source_uuid)
end
