defmodule Commanded.Event.HandleEventTest do
  use ExUnit.Case
  doctest Commanded.Event.Handler

  alias Commanded.ExampleDomain.{BankAccount,AccountBalanceHandler}
  alias Commanded.ExampleDomain.BankAccount.Events.{BankAccountOpened,MoneyDeposited}

  setup do
    EventStore.Storage.reset!
    :ok
  end

  test "event handler is notified of events" do
    {:ok, handler} = Commanded.Event.Handler.start_link("account_balance", AccountBalanceHandler)

  end
end
