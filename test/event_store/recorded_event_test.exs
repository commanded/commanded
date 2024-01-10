defmodule Commanded.EventStore.RecordedEventTest do
  use ExUnit.Case

  alias Commanded.EventStore.RecordedEvent
  alias Commanded.Helpers.EventFactory

  defmodule BankAccountOpened do
    @derive Jason.Encoder
    defstruct [:account_number, :initial_balance]
  end

  setup do
    [event] =
      EventFactory.map_to_recorded_events(
        [
          %BankAccountOpened{account_number: "123", initial_balance: 1_000}
        ],
        1,
        metadata: %{"key1" => "value1", "key2" => "value2"}
      )

    [event: event]
  end

  describe "RecordedEvent struct" do
    test "enrich_metadata/2 should add a number of fields to the metadata", %{event: event} do
      %RecordedEvent{
        event_id: event_id,
        event_number: event_number,
        stream_id: stream_id,
        stream_version: stream_version,
        correlation_id: correlation_id,
        causation_id: causation_id,
        created_at: created_at
      } = event

      enriched_metadata =
        RecordedEvent.enrich_metadata(event,
          additional_metadata: %{
            application: ExampleApplication
          }
        )

      assert enriched_metadata == %{
               # Event string-keyed metadata
               "key1" => "value1",
               "key2" => "value2",
               # Standard event fields
               event_id: event_id,
               event_number: event_number,
               stream_id: stream_id,
               stream_version: stream_version,
               correlation_id: correlation_id,
               causation_id: causation_id,
               created_at: created_at,
               # Additional field
               application: ExampleApplication
             }
    end
  end
end
