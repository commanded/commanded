defmodule Commanded.EventStore.EventData do
  @moduledoc """
  EventData contains the data for a single event before being persisted to storage
  """

  @type t :: %Commanded.EventStore.EventData{
    correlation_id: String.t,
    event_type: String.t,
    data: binary,
    metadata: binary,
  }

  defstruct [
    correlation_id: nil,
    event_type: nil ,
    data: nil,
    metadata: nil,
  ]
end
