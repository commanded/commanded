defmodule Commanded.EventStore.RecordedEvent do
  @moduledoc """
  RecordedEvent contains the persisted data and metadata for a single event.

  Events are immutable once recorded.
  """

  @type t :: %Commanded.EventStore.RecordedEvent{
    event_id: non_neg_integer,
    stream_id: non_neg_integer,
    stream_version: non_neg_integer,
    correlation_id: String.t,
    event_type: String.t,
    data: binary,
    metadata: binary,
    created_at: NaiveDateTime.t,
  }

  defstruct [
    event_id: nil,
    stream_id: nil,
    stream_version: nil,
    correlation_id: nil,
    event_type: nil ,
    data: nil,
    metadata: nil,
    created_at: nil,
  ]
end
