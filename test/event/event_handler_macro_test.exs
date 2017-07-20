defmodule Commanded.Event.EventHandlerMacroTest do
  use Commanded.StorageCase
  use Commanded.EventStore

  defmodule AccountBalanceHandler do
    use Commanded.Event.Handler, name: "account_balance_handler"

    alias Commanded.ExampleDomain.BankAccount.Events.{
      BankAccountOpened,
      MoneyDeposited,
    }

    def handle(%BankAccountOpened{initial_balance: initial_balance}, _metadata) do
      Agent.update(__MODULE__, fn _ -> initial_balance end)
    end

    def handle(%MoneyDeposited{balance: balance}, _metadata) do
      Agent.update(__MODULE__, fn _ -> balance end)
    end

    def current_balance do
      Agent.get(__MODULE__, fn balance -> balance end)
    end
  end

  alias Commanded.Helpers.EventFactory
  alias Commanded.Helpers.Wait
  alias Commanded.ExampleDomain.BankAccount.Events.{BankAccountOpened,MoneyDeposited}

  test "should handle published events" do
    {:ok, _} = Agent.start_link(fn -> 0 end, name: AccountBalanceHandler)
    {:ok, handler} = AccountBalanceHandler.start_link()

    recorded_events =
      [
        %BankAccountOpened{account_number: "ACC123", initial_balance: 1_000},
        %MoneyDeposited{amount: 50, balance: 1_050}
      ]
      |> EventFactory.map_to_recorded_events()

    send(handler, {:events, recorded_events})

    Wait.until(fn ->
      assert AccountBalanceHandler.current_balance == 1_050
    end)
  end
end
