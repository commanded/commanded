defmodule EventStore.EventData do
  @moduledoc """
  EventData contains the data for a single event before being persisted to storage
  """
  
  defstruct correlation_id: nil,
            causation_id: nil,
            event_type: nil ,
            data: nil,
            metadata: nil

  @type t :: %EventStore.EventData{
    correlation_id: String.t,
    causation_id: String.t,
    event_type: String.t,
    data: binary,
    metadata: binary
  }

  def fetch(map, key) when is_map(map) do
    Map.fetch(map, key)
  end

  def get_and_update(map, key, fun) when is_map(map) do
    Map.get_and_update(map, key, fun)
  end
end
