defmodule EventStore.EventData do
  @moduledoc """
  EventData contains the data for a single event before being persisted to storage

  EventStore does not have any built-in serialization.
  The payload and headers for each event should already be serialized to binary data.
  """
  defstruct correlation_id: nil,
            event_type: nil ,
            headers: nil,
            payload: nil
end
