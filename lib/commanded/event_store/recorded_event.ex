defmodule Commanded.EventStore.RecordedEvent do
  @moduledoc """
  Contains the persisted stream identity, type, data, and metadata for a single event.

  Events are immutable once recorded.

  ## Recorded event fields

    - `event_id` - a globally unique UUID to identify the event.

    - `event_number` - a globally unique, monotonically incrementing and gapless
      integer used to order the event amongst all events.

    - `stream_id` - the stream identity for the event.

    - `stream_version` - the version of the stream for the event.

    - `causation_id` - an optional UUID identifier used to identify which
      message you are responding to.

    - `correlation_id` - an optional UUID identifier used to correlate related
      messages.

    - `data` - the serialized event as binary data.

    - `metadata` - the serialized event metadata as binary data.

    - `created_at` - the date/time, in UTC, indicating when the event was
      created.

  """

  @type uuid :: String.t

  @type t :: %Commanded.EventStore.RecordedEvent{
    event_id: uuid(),
    event_number: non_neg_integer(),
    stream_id: String.t,
    stream_version: non_neg_integer(),
    causation_id: uuid(),
    correlation_id: uuid(),
    event_type: String.t,
    data: binary(),
    metadata: binary(),
    created_at: NaiveDateTime.t,
  }

  defstruct [
    :event_id,
    :event_number,
    :stream_id,
    :stream_version,
    :causation_id,
    :correlation_id,
    :event_type,
    :data,
    :metadata,
    :created_at,
  ]
end
