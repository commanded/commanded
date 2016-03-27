defmodule Commanded.Commands.HandleCommandTest do
  use ExUnit.Case
  doctest Commanded.Commands.Handler

  alias Commanded.ExampleDomain.{BankAccount,OpenAccountHandler}
  alias Commanded.ExampleDomain.BankAccount.Commands.OpenAccount

  test "command handler implements behaviour" do
    bank_account =
      BankAccount.new("1")
      |> OpenAccountHandler.handle(%OpenAccount{account_number: "ACC123", initial_balance: 1_000})

    assert bank_account.state.account_number == "ACC123"
    assert length(bank_account.events) == 1
    assert bank_account.version == 1
  end
end
