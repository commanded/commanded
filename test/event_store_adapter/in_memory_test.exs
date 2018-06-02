defmodule Commanded.EventStoreAdapter.InMemoryTest do
  use ExUnit.Case

  alias Commanded.EventStore.Adapters.InMemory
  alias Commanded.EventStore.EventData

  defmodule(BankAccountOpened, do: defstruct([:account_number, :initial_balance]))

  setup do
    default_event_store_adapter = Application.get_env(:commanded, :event_store_adapter)

    Application.put_env(:commanded, :event_store_adapter, InMemory)

    on_exit(fn ->
      Application.put_env(:commanded, :event_store_adapter, default_event_store_adapter)
    end)
  end

  describe "reset!/0" do
    test "wipes all data from memory" do
      {:ok, pid} = InMemory.start_link()
      initial = :sys.get_state(pid)

      {:ok, 1} = InMemory.append_to_stream("stream", 0, [build_event(1)])
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
      event_type: "Elixir.Commanded.EventStore.Adapter.SubscriptionTest.BankAccountOpened",
      data: %BankAccountOpened{account_number: account_number, initial_balance: 1_000},
      metadata: %{"user_id" => "test"}
    }
  end
end
