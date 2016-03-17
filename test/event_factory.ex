defmodule EventStore.EventFactory do
  alias EventStore.{EventData,RecordedEvent}

  defmodule Event do
    defstruct event: nil
  end

  def create_events(number_of_events) when number_of_events > 0 do
    correlation_id = UUID.uuid4()

    1..number_of_events
    |> Enum.map(fn number ->
      %EventData{
        correlation_id: correlation_id,
        event_type: "unit_test_event",
        headers: serialize(%{"user" => "user@example.com"}),
        payload: serialize(%EventStore.EventFactory.Event{event: number})
      }
    end)
  end

  def create_recorded_events(number_of_events, stream_uuid) when number_of_events > 0 do
    correlation_id = UUID.uuid4()

    1..number_of_events
    |> Enum.map(fn number ->
      %RecordedEvent{
        event_id: number,
        stream_id: stream_uuid,
        stream_version: number,
        correlation_id: correlation_id,
        event_type: "unit_test_event",
        headers: serialize(%{"user" => "user@example.com"}),
        payload: serialize(%EventStore.EventFactory.Event{event: number}),
        created_at: :calendar.universal_time
      }
    end)
  end

  def deserialize_events(events) do
    events
    |> Enum.map(fn event ->
      %RecordedEvent{event | payload: deserialize(event.payload), headers: deserialize(event.headers)}
    end)
  end

  # Serialize given Erlang term to binary using Erlang's External Term Format (http://erlang.org/doc/apps/erts/erl_ext_dist.html)
  defp serialize(term) do
    :erlang.term_to_binary(term)
  end

  # Deserialize given binary data to an Erlang term using Erlang's External Term Format (http://erlang.org/doc/apps/erts/erl_ext_dist.html)
  defp deserialize(binary) do
    :erlang.binary_to_term(binary, [:safe])
  end
end
