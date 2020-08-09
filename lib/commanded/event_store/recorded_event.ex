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

    - `data` - the event data deserialized into a struct.

    - `metadata` - a string keyed map of metadata associated with the event.

    - `created_at` - the datetime, in UTC, indicating when the event was
      created.

  """

  alias Commanded.EventStore.RecordedEvent

  @type uuid :: String.t()

  @type t :: %RecordedEvent{
          event_id: uuid(),
          event_number: non_neg_integer(),
          stream_id: String.t(),
          stream_version: non_neg_integer(),
          causation_id: uuid() | nil,
          correlation_id: uuid() | nil,
          event_type: String.t(),
          data: struct(),
          metadata: map(),
          created_at: DateTime.t()
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
    :created_at
  ]

  @doc """
  Enrich the event's metadata with fields from the `RecordedEvent` struct and
  any additional metadata passed as an option.
  """
  @spec enrich_metadata(t(), [{:additional_metadata, map()}]) :: map()
  def enrich_metadata(%RecordedEvent{} = event, opts) do
    %RecordedEvent{
      event_id: event_id,
      event_number: event_number,
      stream_id: stream_id,
      stream_version: stream_version,
      correlation_id: correlation_id,
      causation_id: causation_id,
      created_at: created_at,
      metadata: metadata
    } = event

    %{
      event_id: event_id,
      event_number: event_number,
      stream_id: stream_id,
      stream_version: stream_version,
      correlation_id: correlation_id,
      causation_id: causation_id,
      created_at: created_at
    }
    |> Map.merge(Keyword.get(opts, :additional_metadata, %{}))
    |> Map.merge(metadata || %{})
  end
end
