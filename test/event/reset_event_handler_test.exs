defmodule Commanded.Event.ResetEventHandlerTest do
  use ExUnit.Case

  import Commanded.Assertions.EventAssertions

  alias Commanded.Event.Mapper
  alias Commanded.EventStore
  alias Commanded.ExampleDomain.BankAccount.BankAccountHandler
  alias Commanded.ExampleDomain.BankAccount.Events.BankAccountOpened
  alias Commanded.ExampleDomain.BankApp
  alias Commanded.Helpers.Wait
  alias Commanded.UUID

  describe "reset event handler" do
    setup do
      start_supervised!(BankApp)
      :ok
    end

    test "should be reset when starting from `:origin`" do
      stream_uuid = UUID.uuid4()
      initial_events = [%BankAccountOpened{account_number: "ACC123", initial_balance: 1_000}]

      :ok = EventStore.append_to_stream(BankApp, stream_uuid, 0, to_event_data(initial_events))

      handler = start_supervised!(BankAccountHandler)

      Wait.until(fn ->
        assert BankAccountHandler.current_accounts() == ["ACC123"]
      end)

      :ok = BankAccountHandler.change_prefix("PREF_")

      send(handler, :reset)

      Wait.until(fn ->
        assert BankAccountHandler.current_accounts() == ["PREF_ACC123"]
      end)
    end

    test "should be reset when starting from `:current`" do
      stream_uuid = UUID.uuid4()

      # Ignored initial events
      initial_events = [%BankAccountOpened{account_number: "ACC123", initial_balance: 1_000}]
      :ok = EventStore.append_to_stream(BankApp, stream_uuid, 0, to_event_data(initial_events))

      handler = start_supervised!({BankAccountHandler, start_from: :current})

      Wait.until(fn ->
        assert BankAccountHandler.current_accounts() == []
      end)

      :ok = BankAccountHandler.change_prefix("PREF_")

      send(handler, :reset)

      new_event = [%BankAccountOpened{account_number: "ACC1234", initial_balance: 1_000}]
      :ok = EventStore.append_to_stream(BankApp, stream_uuid, 1, to_event_data(new_event))

      wait_for_event(BankApp, BankAccountOpened, fn event, recorded_event ->
        event.account_number == "ACC1234" and recorded_event.event_number == 2
      end)

      Wait.until(fn ->
        assert BankAccountHandler.current_accounts() == ["PREF_ACC1234"]
      end)
    end
  end

  defp to_event_data(events) do
    Mapper.map_to_event_data(events,
      causation_id: UUID.uuid4(),
      correlation_id: UUID.uuid4(),
      metadata: %{}
    )
  end
end
