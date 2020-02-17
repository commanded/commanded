defmodule Commanded.Commands.DispatchCommandTest do
  use ExUnit.Case

  alias Commanded.ExampleDomain.BankApp
  alias Commanded.ExampleDomain.BankRouter
  alias Commanded.ExampleDomain.BankAccount.Commands.OpenAccount
  alias Commanded.Helpers.CommandAuditMiddleware

  setup do
    start_supervised!(CommandAuditMiddleware)
    start_supervised!(BankApp)

    :ok
  end

  describe "dispatch command" do
    test "should be dispatched via an application" do
      command = %OpenAccount{account_number: "ACC123", initial_balance: 1_000}

      assert :ok = BankApp.dispatch(command)
    end

    test "should be dispatched via a router" do
      command = %OpenAccount{account_number: "ACC123", initial_balance: 1_000}

      assert :ok = BankRouter.dispatch(command, application: BankApp)
    end
  end
end
