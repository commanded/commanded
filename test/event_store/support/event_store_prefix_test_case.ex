defmodule Commanded.EventStore.EventStorePrefixTestCase do
  import Commanded.SharedTestCase

  define_tests do
    alias Commanded.EventStore.EventData
    alias Commanded.UUID

    defmodule BankAccountOpened do
      @derive Jason.Encoder
      defstruct [:account_number, :initial_balance]
    end

    describe "event store prefix" do
      setup do
        {:ok, event_store_meta1} = start_event_store(name: :prefix1, prefix: "prefix1")
        {:ok, event_store_meta2} = start_event_store(name: :prefix2, prefix: "prefix2")

        [event_store_meta1: event_store_meta1, event_store_meta2: event_store_meta2]
      end

      test "should append events to named event store", %{
        event_store: event_store,
        event_store_meta1: event_store_meta1,
        event_store_meta2: event_store_meta2
      } do
        events = build_events(1)

        assert :ok == event_store.append_to_stream(event_store_meta1, "stream", 0, events)

        assert {:error, :stream_not_found} ==
                 event_store.stream_forward(event_store_meta2, "stream")
      end
    end

    defp build_events(count, correlation_id \\ UUID.uuid4(), causation_id \\ UUID.uuid4())

    defp build_events(count, correlation_id, causation_id) do
      for account_number <- 1..count,
          do: build_event(account_number, correlation_id, causation_id)
    end

    defp build_event(account_number, correlation_id, causation_id) do
      %EventData{
        correlation_id: correlation_id,
        causation_id: causation_id,
        event_type: "#{__MODULE__}.BankAccountOpened",
        data: %BankAccountOpened{account_number: account_number, initial_balance: 1_000},
        metadata: %{"metadata" => "value"}
      }
    end
  end
end
