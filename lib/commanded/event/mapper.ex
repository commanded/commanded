defmodule Commanded.Event.Mapper do
  @moduledoc """
  Map events to/from the structs used for persistence.

  ## Example

  Map domain event structs to `Commanded.EventStore.EventData` structs in
  preparation for appending to the configured event store:

      events = [%ExampleEvent1{}, %ExampleEvent2{}]
      event_data = Commanded.Event.Mapper.map_to_event_data(events)

      :ok = Commanded.EventStore.append_to_stream("stream-1234", :any_version, event_data)

  """

  alias Commanded.EventStore.TypeProvider
  alias Commanded.EventStore.{EventData, RecordedEvent}

  @type event :: struct

  @doc """
  Map a domain event (or list of events) to an
  `Commanded.EventStore.EventData` struct (or list of structs).

  Optionally, include the `causation_id`, `correlation_id`, and `metadata`
  associated with the event(s).

  ## Examples

      event_data = Commanded.Event.Mapper.map_to_event_data(%ExampleEvent{})

      event_data =
        Commanded.Event.Mapper.map_to_event_data(
          [
            %ExampleEvent1{},
            %ExampleEvent2{}
          ],
          causation_id: Commanded.UUID.uuid4(),
          correlation_id: Commanded.UUID.uuid4(),
          metadata: %{"user_id" => user_id}
        )

  """
  def map_to_event_data(events, fields \\ [])

  @spec map_to_event_data(list(event), Keyword.t()) :: list(EventData.t())
  def map_to_event_data(events, fields) when is_list(events) do
    Enum.map(events, &map_to_event_data(&1, fields))
  end

  @spec map_to_event_data(struct, Keyword.t()) :: EventData.t()
  def map_to_event_data(event, fields) do
    %EventData{
      causation_id: Keyword.get(fields, :causation_id),
      correlation_id: Keyword.get(fields, :correlation_id),
      event_type: TypeProvider.to_string(event),
      data: event,
      metadata: Keyword.get(fields, :metadata, %{})
    }
  end

  @doc """
  Map a list of `Commanded.EventStore.RecordedEvent` structs to their event data.
  """
  @spec map_from_recorded_events(list(RecordedEvent.t())) :: [event]
  def map_from_recorded_events(recorded_events) when is_list(recorded_events) do
    Enum.map(recorded_events, &map_from_recorded_event/1)
  end

  @doc """
  Map an `Commanded.EventStore.RecordedEvent` struct to its event data.
  """
  @spec map_from_recorded_event(RecordedEvent.t()) :: event
  def map_from_recorded_event(%RecordedEvent{data: data}), do: data
end
