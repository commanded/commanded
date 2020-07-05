defmodule Commanded.Event.Upcast do
  @moduledoc false

  alias Commanded.Event.Upcaster
  alias Commanded.EventStore.RecordedEvent

  def upcast_event_stream(%Stream{} = event_stream) do
    Stream.map(event_stream, &upcast_event/1)
  end

  def upcast_event_stream(event_stream) do
    Enum.map(event_stream, &upcast_event/1)
  end

  @enrich_metadata_fields [
    :event_id,
    :event_number,
    :stream_id,
    :stream_version,
    :correlation_id,
    :causation_id,
    :created_at
  ]

  defp upcast_event(%RecordedEvent{} = event) do
    %RecordedEvent{data: data, metadata: metadata} = event

    enriched_metadata =
      event
      |> Map.from_struct()
      |> Map.take(@enrich_metadata_fields)
      |> Map.merge(metadata || %{})

    %RecordedEvent{event | data: Upcaster.upcast(data, enriched_metadata)}
  end
end
