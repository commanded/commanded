defmodule Commanded.EventStore.RecordedEventTest do
  use ExUnit.Case

  alias Commanded.EventStore.RecordedEvent
  alias Commanded.Helpers.EventFactory

  defmodule BankAccountOpened do
    @derive Jason.Encoder
    defstruct [:account_number, :initial_balance]
  end

  setup do
    metadata = %{"key" => "value"}

    [event] =
      EventFactory.map_to_recorded_events(
        [%BankAccountOpened{account_number: "123", initial_balance: 1_000}],
        1,
        metadata: metadata
      )

    enriched_metadata =
      RecordedEvent.enrich_metadata(event,
        additional_metadata: %{application: ExampleApplication}
      )

    [event: event, enriched_metadata: enriched_metadata]
  end

  test "enrich_metadata/2 should add a number of fields to the metadata",
       %{
         event: event,
         enriched_metadata: enriched_metadata
       } do
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

    expected_enriched_metadata =
      Map.merge(
        metadata,
        %{
          # standard fields
          event_id: event_id,
          event_number: event_number,
          stream_id: stream_id,
          stream_version: stream_version,
          correlation_id: correlation_id,
          causation_id: causation_id,
          created_at: created_at,
          #
          # additional field
          application: ExampleApplication
        }
      )

    assert expected_enriched_metadata == enriched_metadata
  end

  test "deplete_metadata/2 should stip additional fields out of enriched_metadata map",
       %{
         event: %{metadata: metadata} = _event,
         enriched_metadata: enriched_metadata
       } do
    assert metadata == RecordedEvent.deplete_metadata(enriched_metadata, [:application])
  end
end
