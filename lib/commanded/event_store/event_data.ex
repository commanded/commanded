defmodule Commanded.EventStore.EventData do
  @moduledoc """
  EventData contains the data for a single event before being persisted to
  storage.
  """

  @type uuid :: String.t()

  @type t :: %Commanded.EventStore.EventData{
          event_id: uuid(),
          causation_id: uuid(),
          correlation_id: uuid(),
          event_type: String.t(),
          data: struct(),
          metadata: map()
        }

  defstruct [
    :event_id,
    :causation_id,
    :correlation_id,
    :event_type,
    :data,
    :metadata
  ]
end
