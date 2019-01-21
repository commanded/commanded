defmodule Commanded.Helpers.EventFactory do
  @moduledoc false
  alias Commanded.EventStore.RecordedEvent

  def map_to_recorded_events(events, initial_event_number \\ 1) do
    stream_id = UUID.uuid4()
    causation_id = UUID.uuid4()
    correlation_id = UUID.uuid4()
    fields = [causation_id: causation_id, correlation_id: correlation_id, metadata: %{}]

    events
    |> Commanded.Event.Mapper.map_to_event_data(fields)
    |> Enum.with_index(initial_event_number)
    |> Enum.map(fn {event, index} ->
      %RecordedEvent{
        event_id: UUID.uuid4(),
        event_number: index,
        stream_id: stream_id,
        stream_version: index,
        causation_id: event.causation_id,
        correlation_id: event.correlation_id,
        event_type: event.event_type,
        data: event.data,
        metadata: event.metadata,
        created_at: now()
      }
    end)
  end

  defp now, do: DateTime.utc_now() |> DateTime.to_naive()
end
