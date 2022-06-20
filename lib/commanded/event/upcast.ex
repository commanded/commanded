defmodule Commanded.Event.Upcast do
  @moduledoc false

  alias Commanded.Event.Upcaster
  alias Commanded.EventStore.RecordedEvent

  def upcast_event_stream(event_stream, opts \\ [])

  def upcast_event_stream(%Stream{} = event_stream, opts),
    do: Stream.map(event_stream, &upcast_event(&1, opts))

  def upcast_event_stream(event_stream, opts),
    do: Enum.map(event_stream, &upcast_event(&1, opts))

  def upcast_event(%RecordedEvent{} = event, opts) do
    %RecordedEvent{data: data} = event

    enriched_metadata = RecordedEvent.enrich_metadata(event, opts)

    %RecordedEvent{event | data: Upcaster.upcast(data, enriched_metadata)}
  end
end
