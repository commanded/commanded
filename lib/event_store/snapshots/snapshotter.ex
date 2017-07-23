defmodule EventStore.Snapshots.Snapshotter do
  @moduledoc """
  Record and read snapshots of process state
  """

  alias EventStore.Snapshots.SnapshotData
  alias EventStore.Storage

  @doc """
  Read a snapshot, if available, for a given source
  """
  def read_snapshot(source_uuid) do
    case Storage.read_snapshot(source_uuid) do
      {:ok, snapshot} -> {:ok, SnapshotData.deserialize(snapshot)}
      reply -> reply
    end
  end

  @doc """
  Record a snapshot containing data and metadata for a given source

  Returns `:ok` on success
  """
  def record_snapshot(%SnapshotData{} = snapshot) do
    snapshot
    |> SnapshotData.serialize()
    |> Storage.record_snapshot()
  end

  @doc """
  Delete a previously recorded snapshot for a given source

  Returns `:ok` on success
  """
  def delete_snapshot(source_uuid), do: Storage.delete_snapshot(source_uuid)
end
