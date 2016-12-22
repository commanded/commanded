defmodule Commanded.EventStore.SnapshotData do
    @moduledoc """
  Snapshot data
  """
    
  defstruct source_uuid: nil,
            source_version: nil,
            source_stream_id: nil,
            source_type: nil,
            data: nil,
            metadata: nil,
            created_at: nil

  @type t :: %Commanded.EventStore.SnapshotData{
    source_uuid: String.t,
    source_version: non_neg_integer,
    source_stream_id: String.t,
    source_type: String.t,
    data: binary,
    metadata: binary,
    created_at: NaiveDateTime.t
  }
end
