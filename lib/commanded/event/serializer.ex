defmodule Commanded.Event.Serializer do
  def map_to_event_data(events, correlation_id) when is_list(events) do
    Enum.map(events, &map_to_event_data(&1, correlation_id))
  end

  def map_to_event_data(event, correlation_id) do
    %EventStore.EventData{
      correlation_id: correlation_id,
      event_type: Atom.to_string(event.__struct__),
      headers: nil,
      payload: serialize(event)
    }
  end

  def map_from_recorded_events(recorded_events) when is_list(recorded_events) do
    Enum.map(recorded_events, &map_from_recorded_event/1)
  end

  def map_from_recorded_event(%EventStore.RecordedEvent{event_type: event_type, payload: payload}) do
    type =
      event_type
      |> String.to_atom
      |> struct

    deserialize(payload, type)
  end

  defp serialize(data) do
    Poison.encode!(data)
  end

  defp deserialize(data, type) do
    Poison.decode!(data, as: type)
  end
end
