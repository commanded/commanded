defmodule Commanded.Commands.HandleCommandTest do
  use Commanded.StorageCase
  doctest Commanded.Commands.Handler

  alias Commanded.ExampleDomain.{BankAccount,OpenAccountHandler}
  alias Commanded.ExampleDomain.BankAccount.Commands.OpenAccount
  alias Commanded.ExampleDomain.BankAccount.Events.BankAccountOpened

  test "command handler implements behaviour" do
    initial_state = %BankAccount{}
    event = OpenAccountHandler.handle(initial_state, %OpenAccount{account_number: "ACC123", initial_balance: 1_000})

    assert event == %BankAccountOpened{account_number: "ACC123", initial_balance: 1_000}
    assert BankAccount.apply(initial_state, event) == %BankAccount{
      account_number: "ACC123",
      balance: 1_000,
      state: :active,
    }
  end
end
