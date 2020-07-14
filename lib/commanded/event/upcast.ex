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

  defp upcast_event(%RecordedEvent{} = event) do
    %RecordedEvent{data: data} = event

    enriched_metadata = RecordedEvent.enrich_metadata(event)

    %RecordedEvent{event | data: Upcaster.upcast(data, enriched_metadata)}
  end
end
