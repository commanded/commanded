defmodule EventStore.EventData do
  defstruct event_id: nil,
    stream_id: nil,
    stream_version: nil,
    correlation_id: nil,
    event_type: nil ,
    headers: nil,
    payload: nil,
    created_at: nil
end
