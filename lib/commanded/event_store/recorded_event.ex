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

  @type domain_event :: struct()

  @type event_id :: uuid()
  @type event_number :: non_neg_integer()
  @type stream_id :: String.t()
  @type stream_version :: non_neg_integer()
  @type causation_id :: uuid() | nil
  @type correlation_id :: uuid() | nil
  @type event_type :: String.t()
  @type data :: domain_event()
  @type metadata :: map()
  @type created_at :: DateTime.t()

  @type t :: %RecordedEvent{
          event_id: event_id(),
          event_number: event_number(),
          stream_id: stream_id(),
          stream_version: stream_version(),
          causation_id: causation_id(),
          correlation_id: correlation_id(),
          event_type: event_type(),
          data: data(),
          metadata: metadata(),
          created_at: created_at()
        }

  @type enriched_metadata :: %{
          :event_id => event_id(),
          :event_number => event_number(),
          :stream_id => stream_id(),
          :stream_version => stream_version(),
          :correlation_id => correlation_id(),
          :causation_id => causation_id(),
          :created_at => created_at(),
          optional(atom()) => term(),
          optional(String.t()) => term()
        }

  @type additional_fields_to_deplete :: [atom()]

  @enriched_metadata_fields ~w(
    event_id
    event_number
    stream_id
    stream_version
    correlation_id
    causation_id
    created_at
  )a

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
  @spec enrich_metadata(t(), [{:additional_metadata, map()}]) :: enriched_metadata()
  def enrich_metadata(%RecordedEvent{metadata: metadata} = event, opts) do
    event
    |> Map.take(@enriched_metadata_fields)
    |> Map.merge(Keyword.get(opts, :additional_metadata, %{}))
    |> Map.merge(metadata || %{})
  end

  @doc """
  Deplete the enriched part of the event's metadata added by `c:enrhich_metadata/2`
  and all additional fields in the list passed as the last parameter.
  """
  @spec deplete_metadata(enriched_metadata(), additional_fields_to_deplete()) :: map()
  def deplete_metadata(enriched_metadata, additional_fields_to_deplete \\ []) do
    enriched_metadata
    |> Map.drop(@enriched_metadata_fields)
    |> Map.drop(additional_fields_to_deplete)
  end
end
