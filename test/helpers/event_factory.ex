defmodule Commanded.Helpers.EventFactory do
  @moduledoc false
  alias Commanded.EventStore.RecordedEvent

  def map_to_recorded_events(events) do
    stream_id = UUID.uuid4()
    causation_id = UUID.uuid4()
    correlation_id = UUID.uuid4()

    events
    |> Commanded.Event.Mapper.map_to_event_data(causation_id, correlation_id, %{})
    |> Enum.with_index(1)
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
        created_at: now(),
      }
    end)
  end

  defp now, do: DateTime.utc_now() |> DateTime.to_naive()
end
