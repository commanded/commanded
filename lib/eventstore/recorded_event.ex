defmodule EventStore.RecordedEvent do
  @moduledoc """
  RecordedEvent contains the persisted data for a single event

  Events are immutable once recorded.
  """
  defstruct event_id: nil,
            stream_id: nil,
            stream_version: nil,
            correlation_id: nil,
            event_type: nil ,
            headers: nil,
            payload: nil,
            created_at: nil
end
