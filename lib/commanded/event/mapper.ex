defmodule Commanded.Event.Mapper do
  @moduledoc """
  Map raw events to event data structs ready to be persisted to the event store.
  """

  def map_to_event_data(events, correlation_id, causation_id) when is_list(events) do
    Enum.map(events, &map_to_event_data(&1, correlation_id, causation_id))
  end

  def map_to_event_data(event, correlation_id, causation_id) do
    %EventStore.EventData{
      correlation_id: correlation_id,
      causation_id: causation_id,
      event_type: Atom.to_string(event.__struct__),
      data: event,
      metadata: %{}
    }
  end

  def map_from_recorded_events(recorded_events) when is_list(recorded_events) do
    Enum.map(recorded_events, &map_from_recorded_event/1)
  end

  def map_from_recorded_event(%EventStore.RecordedEvent{data: data}) do
    data
  end
end
