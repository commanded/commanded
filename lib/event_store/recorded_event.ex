defmodule EventStore.RecordedEvent do
  @moduledoc """
  RecordedEvent contains the persisted data and metadata for a single event.

  Events are immutable once recorded.
  """

  use EventStore.Serializer

  alias EventStore.RecordedEvent

  @type t :: %RecordedEvent{
    event_id: non_neg_integer,
    stream_id: non_neg_integer,
    stream_version: non_neg_integer,
    correlation_id: String.t,
    causation_id: String.t,
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
    causation_id: nil,
    event_type: nil,
    data: nil,
    metadata: nil,
    created_at: nil,
  ]

  def deserialize(%RecordedEvent{data: data, metadata: metadata, event_type: event_type} = recorded_event) do
    %RecordedEvent{recorded_event |
      data: @serializer.deserialize(data, type: event_type),
      metadata: @serializer.deserialize(metadata, [])
    }
  end

  def fetch(map, key) when is_map(map) do
    Map.fetch(map, key)
  end

  def get_and_update(map, key, fun) when is_map(map) do
    Map.get_and_update(map, key, fun)
  end
end
