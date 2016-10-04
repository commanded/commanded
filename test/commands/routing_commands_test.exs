defmodule Commanded.Commands.RoutingCommandsTest do
  use Commanded.StorageCase
  doctest Commanded.Commands.Router

  alias Commanded.ExampleDomain.BankAccount
  alias Commanded.ExampleDomain.{OpenAccountHandler,DepositMoneyHandler}
  alias Commanded.ExampleDomain.BankAccount.Commands.{OpenAccount,DepositMoney}

  defmodule UnregisteredCommand do
    defstruct aggregate_uuid: UUID.uuid4
  end

  defmodule ExampleRouter do
    use Commanded.Commands.Router

    dispatch OpenAccount, to: OpenAccountHandler, aggregate: BankAccount, identity: :account_number
    dispatch DepositMoney, to: DepositMoneyHandler, aggregate: BankAccount, identity: :account_number
  end

  test "should dispatch command to registered handler" do
    :ok = ExampleRouter.dispatch(%OpenAccount{account_number: "ACC123", initial_balance: 1_000})
  end

  test "should fail to dispatch unregistered command" do
    {:error, :unregistered_command} = ExampleRouter.dispatch(%UnregisteredCommand{})
  end

  test "should prevent duplicate registrations for a command" do
    # compile time safety net to prevent duplicate command registrations
    assert_raise RuntimeError, "duplicate command registration for: Elixir.Commanded.ExampleDomain.BankAccount.Commands.OpenAccount", fn ->
      Code.eval_string """
        alias Commanded.ExampleDomain.BankAccount.Commands.{OpenAccount,DepositMoney}

        defmodule DuplicateRouter do
          use Commanded.Commands.Router

          dispatch OpenAccount, to: OpenAccountHandler, aggregate: BankAccount, identity: :account_number
          dispatch OpenAccount, to: OpenAccountHandler, aggregate: BankAccount, identity: :account_number
        end
      """
    end
  end

  # test "should fail to dispatch command without an identity"
  # test "should fail to dispatch command with nil identity
end
