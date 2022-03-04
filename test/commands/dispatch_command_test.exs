defmodule Commanded.Commands.DispatchCommandTest do
  use ExUnit.Case

  alias Commanded.ExampleDomain.BankAccount.Commands.{LockAccount, OpenAccount}
  alias Commanded.ExampleDomain.{BankApp, BankRouter}
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

    test "should return aggregate execution timeout after timeout with little delta" do
      command = %OpenAccount{account_number: "ACC123", initial_balance: 1_000}
      assert :ok = BankRouter.dispatch(command, application: BankApp)

      # change timeout from default value
      timeout = 50

      {time_in_microseconds, {:error, :aggregate_execution_timeout}} =
        :timer.tc(fn ->
          try do
            command = %LockAccount{account_number: "ACC123"}

            BankRouter.dispatch(command, application: BankApp, timeout: timeout)
          rescue
            e -> e
          end
        end)

      assert_in_delta time_in_microseconds / 1_000, timeout, 10
    end
  end
end
