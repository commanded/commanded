defmodule Commanded.Event.EventHandlerMacroTest do
  use Commanded.StorageCase

  alias Commanded.Event.IgnoredEvent
  alias Commanded.Helpers.{EventFactory, ProcessHelper, Wait}
  alias Commanded.ExampleDomain.BankAccount.Events.{BankAccountOpened, MoneyDeposited}
  alias Commanded.ExampleDomain.BankAccount.AccountBalanceHandler

  setup do
    handler = start_supervised!(AccountBalanceHandler)

    [handler: handler]
  end

  describe "event handler" do
    test "should handle published events", %{handler: handler} do
      Wait.until(fn ->
        assert AccountBalanceHandler.subscribed?()
      end)

      recorded_events =
        [
          %BankAccountOpened{account_number: "ACC123", initial_balance: 1_000},
          %MoneyDeposited{amount: 50, balance: 1_050},
          %IgnoredEvent{name: "ignored"}
        ]
        |> EventFactory.map_to_recorded_events()

      send(handler, {:events, recorded_events})

      Wait.until(fn ->
        assert AccountBalanceHandler.current_balance() == 1_050
      end)
    end

    test "should provide `__name__/0` function" do
      assert AccountBalanceHandler.__name__() ==
               "Commanded.ExampleDomain.BankAccount.AccountBalanceHandler"
    end
  end
end
