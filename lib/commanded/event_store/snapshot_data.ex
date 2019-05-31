defmodule Commanded.EventStore.SnapshotData do
  @moduledoc """
  Snapshot data
  """

  @type t :: %Commanded.EventStore.SnapshotData{
          source_uuid: String.t(),
          source_version: non_neg_integer,
          source_type: String.t(),
          data: binary,
          metadata: binary,
          created_at: DateTime.t()
        }

  defstruct [
    :source_uuid,
    :source_version,
    :source_type,
    :data,
    :metadata,
    :created_at
  ]
end
