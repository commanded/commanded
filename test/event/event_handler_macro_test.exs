defmodule Commanded.Event.EventHandlerMacroTest do
  use Commanded.StorageCase

  defmodule IgnoredEvent do
    defstruct [name: nil]
  end

  alias Commanded.ExampleDomain.AccountBalanceHandler
  alias Commanded.ExampleDomain.BankAccount.Events.{BankAccountOpened,MoneyDeposited}
  alias Commanded.Helpers.EventFactory
  alias Commanded.Helpers.Wait

  setup do
    on_exit fn ->
      Commanded.Helpers.Process.shutdown(AccountBalanceHandler)
    end
  end

  test "should handle published events" do
    {:ok, handler} = AccountBalanceHandler.start_link()

    recorded_events =
      [
        %BankAccountOpened{account_number: "ACC123", initial_balance: 1_000},
        %MoneyDeposited{amount: 50, balance: 1_050},
        %IgnoredEvent{name: "ignored"},
      ]
      |> EventFactory.map_to_recorded_events()

    send(handler, {:events, recorded_events})

    Wait.until(fn ->
      assert AccountBalanceHandler.current_balance == 1_050
    end)
  end
end
