defmodule Commanded.Commands.HandleCommandTest do
  use Commanded.StorageCase
  doctest Commanded.Commands.Handler

  alias Commanded.ExampleDomain.{BankAccount,OpenAccountHandler}
  alias Commanded.ExampleDomain.BankAccount.Commands.OpenAccount

  test "command handler implements behaviour" do
    {:ok, account} =
      BankAccount.new("1")
      |> OpenAccountHandler.handle(%OpenAccount{account_number: "ACC123", initial_balance: 1_000})

    assert account.state.account_number == "ACC123"
    assert length(account.pending_events) == 1
    assert account.version == 1
  end
end
