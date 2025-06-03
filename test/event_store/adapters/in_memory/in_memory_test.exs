defmodule Commanded.EventStore.Adapters.InMemoryTest do
  use Commanded.EventStore.InMemoryTestCase

  alias Commanded.EventStore.Adapters.InMemory
  alias Commanded.EventStore.EventData
  alias Commanded.UUID

  defmodule BankAccountOpened do
    @derive Jason.Encoder
    defstruct [:account_number, :initial_balance]
  end

  describe "reset!/0" do
    test "wipes all data from memory", %{event_store_meta: event_store_meta} do
      pid = Process.whereis(InMemory.EventStore)
      initial = :sys.get_state(pid)
      events = [build_event(1)]

      :ok = InMemory.append_to_stream(event_store_meta, "stream", 0, events)
      after_event = :sys.get_state(pid)

      InMemory.reset!(InMemory)
      after_reset = :sys.get_state(pid)

      assert initial == after_reset
      assert length(Map.get(after_event.streams, "stream")) == 1
      assert after_reset.streams == %{}
    end
  end

  describe "ack_event/3" do
    test "acknowledges one event", %{event_store_meta: event_store_meta} do
      pid = Process.whereis(InMemory.EventStore)
      initial = :sys.get_state(pid)
      assert initial.next_event_number == 1

      {:ok, subscription} =
        InMemory.subscribe_to(event_store_meta, "stream", "subscriber", self(), :origin, [])

      :ok = InMemory.append_to_stream(event_store_meta, "stream", 0, build_events(1))
      final = :sys.get_state(pid)
      assert_receive {:events, received_events}
      assert :ok == InMemory.ack_event(event_store_meta, subscription, List.last(received_events))
      assert final.next_event_number == 2
    end
  end

  defp build_event(account_number) do
    %EventData{
      causation_id: UUID.uuid4(),
      correlation_id: UUID.uuid4(),
      event_type: "#{__MODULE__}.BankAccountOpened",
      data: %BankAccountOpened{account_number: account_number, initial_balance: 1_000},
      metadata: %{"user_id" => "test"}
    }
  end

  defp build_events(count) do
    for account_number <- 1..count, do: build_event(account_number)
  end
end
