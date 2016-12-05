defmodule Commanded.Event.RecordedEvent do
  @moduledoc """
  RecordedEvent contains the persisted data and metadata for a single event.

  Events are immutable once recorded.
  """

  @type t :: %Commanded.Event.RecordedEvent{
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

  def extract_events_data(recorded_events) when is_list(recorded_events), do:
    Enum.map(recorded_events, &extract_event_data/1)

  def extract_event_data(%EventStore.RecordedEvent{data: data}), do:
    data

end
