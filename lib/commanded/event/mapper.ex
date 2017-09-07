defmodule Commanded.Event.Mapper do
  @moduledoc """
  Map raw events to event data structs ready to be persisted to the event store.
  """

  alias Commanded.EventStore.TypeProvider
  alias Commanded.EventStore.{
    EventData,
    RecordedEvent,
  }

  def map_to_event_data(event, correlation_id \\ nil, causation_id \\ nil, metadata \\ %{})

  def map_to_event_data(events, correlation_id, causation_id, metadata) when is_list(events) do
    Enum.map(events, &map_to_event_data(&1, correlation_id, causation_id, metadata))
  end

  def map_to_event_data(event, correlation_id, causation_id, metadata) do
    %EventData{
      correlation_id: correlation_id,
      causation_id: causation_id,
      event_type: TypeProvider.to_string(event),
      data: event,
      metadata: metadata,
    }
  end

  def map_from_recorded_events(recorded_events) when is_list(recorded_events) do
    Enum.map(recorded_events, &map_from_recorded_event/1)
  end

  def map_from_recorded_event(%RecordedEvent{data: data}), do: data
end
