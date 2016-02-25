defmodule EventStore.EventFactory do
  alias EventStore.EventData

  defmodule Event do
    defstruct event: nil
  end

  def create_events(number_of_events) do
    correlation_id = UUID.uuid4()

    1..number_of_events
    |> Enum.map(fn number ->
      %EventData{
        correlation_id: correlation_id,
        headers: %{"user" => "user@example.com"},
        payload: %EventStore.EventFactory.Event{event: number}
      }
    end)
  end
end
