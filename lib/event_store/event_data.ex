defmodule EventStore.EventData do
  @moduledoc """
  EventData contains the data for a single event before being persisted to storage
  """
  defstruct correlation_id: nil,
            event_type: nil ,
            data: nil,
            metadata: nil
end