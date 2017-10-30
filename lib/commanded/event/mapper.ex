defmodule Commanded.Event.Mapper do
  @moduledoc false

  alias Commanded.EventStore.TypeProvider
  alias Commanded.EventStore.{EventData,RecordedEvent}

  def map_to_event_data(events, causation_id, correlation_id, metadata)
    when is_list(events)
  do
    Enum.map(events, &map_to_event_data(&1, causation_id, correlation_id, metadata))
  end

  def map_to_event_data(event, causation_id, correlation_id, metadata) do
    %EventData{
      causation_id: causation_id,
      correlation_id: correlation_id,
      event_type: TypeProvider.to_string(event),
      data: event,
      metadata: metadata,
    }
  end

  def map_from_recorded_events(recorded_events)
    when is_list(recorded_events)
  do
    Enum.map(recorded_events, &map_from_recorded_event/1)
  end

  def map_from_recorded_event(%RecordedEvent{data: data}),
    do: data
end
