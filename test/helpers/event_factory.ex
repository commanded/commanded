defmodule Commanded.Helpers.EventFactory do
  def map_to_recorded_events(events) do
    events
    |> Commanded.Event.Serializer.map_to_event_data(UUID.uuid4)
    |> Enum.with_index(1)
    |> Enum.map(fn {event, index} ->
      %EventStore.RecordedEvent{
        event_id: index,
        stream_id: 1,
        stream_version: index,
        correlation_id: event.correlation_id,
        event_type: event.event_type,
        headers: event.headers,
        payload: event.payload,
        created_at: :calendar.universal_time
      }
    end)
  end
end
