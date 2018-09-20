defmodule Commanded.EventStore.Adapters.InMemoryTest do
  use ExUnit.Case

  alias Commanded.EventStore.Adapters.InMemory
  alias Commanded.EventStore.EventData

  defmodule BankAccountOpened do
    defstruct [:account_number, :initial_balance]
  end

  setup do
    InMemory.reset!()
    :ok
  end

  describe "reset!/0" do
    test "wipes all data from memory" do
      pid = Process.whereis(InMemory)
      initial = :sys.get_state(pid)
      events = [build_event(1)]

      :ok = InMemory.append_to_stream("stream", 0, events)
      after_event = :sys.get_state(pid)

      InMemory.reset!()
      after_reset = :sys.get_state(pid)

      assert initial == after_reset
      assert length(Map.get(after_event.streams, "stream")) == 1
      assert after_reset.streams == %{}
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
end
