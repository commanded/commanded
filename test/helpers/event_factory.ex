defmodule Commanded.Helpers.EventFactory do
  def map_to_recorded_events(events) do
    events
    |> Commanded.Event.Mapper.map_to_event_data(UUID.uuid4)
    |> Enum.with_index(1)
    |> Enum.map(fn {event, index} ->
      %Commanded.EventStore.RecordedEvent{
        event_id: index,
        stream_id: 1,
        stream_version: index,
        correlation_id: event.correlation_id,
        event_type: event.event_type,
        data: event.data,
        metadata: event.metadata,
        created_at: now(),
      }
    end)
  end

  defp now, do: DateTime.utc_now |> DateTime.to_naive
end
