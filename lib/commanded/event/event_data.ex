defmodule Commanded.Event.EventData do
  @moduledoc """
  EventData contains the data for a single event before being persisted to storage
  """
  defstruct correlation_id: nil,
            event_type: nil ,
            data: nil,
            metadata: nil

  @type t :: %Commanded.Event.EventData{
    correlation_id: String.t,
    event_type: String.t,
    data: binary,
    metadata: binary
  }


  @doc "Generate event data structure from raw events and correlation id"
  def generate_event_data(events, correlation_id) when is_list(events), do:
    Enum.map(events, &generate_event_data(&1, correlation_id))


  def generate_event_data(event, correlation_id) do
    %Commanded.Event.EventData{
      correlation_id: correlation_id,
      event_type: Atom.to_string(event.__struct__),
      data: event,
      metadata: %{}
    }
  end



end
