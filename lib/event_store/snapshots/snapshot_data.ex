defmodule EventStore.Snapshots.SnapshotData do
  @moduledoc """
  Snapshot data
  """
  defstruct source_uuid: nil,
            source_version: nil,
            source_type: nil,
            data: nil,
            metadata: nil,
            created_at: nil
end
