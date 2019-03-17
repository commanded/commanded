defmodule Commanded.Event.Upcasting do
  alias Commanded.EventStore.RecordedEvent

  def upcast_event_stream(%Stream{} = event_stream) do
    Stream.map(event_stream, &upcast_event/1)
  end

  def upcast_event(%RecordedEvent{data: data, metadata: metadata} = event) do
    %{event | data: Commanded.Event.Upcaster.upcast(data, metadata)}
  end
end
