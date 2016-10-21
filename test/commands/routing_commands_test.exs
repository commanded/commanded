defmodule Commanded.Commands.RoutingCommandsTest do
  use Commanded.StorageCase
  doctest Commanded.Commands.Router

  alias Commanded.ExampleDomain.BankAccount
  alias Commanded.ExampleDomain.{OpenAccountHandler,DepositMoneyHandler,WithdrawMoneyHandler}
  alias Commanded.ExampleDomain.BankAccount.Commands.{OpenAccount,CloseAccount,DepositMoney,WithdrawMoney}

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
        alias Commanded.ExampleDomain.BankAccount.Commands.OpenAccount

        defmodule DuplicateRouter do
          use Commanded.Commands.Router

          dispatch OpenAccount, to: OpenAccountHandler, aggregate: BankAccount, identity: :account_number
          dispatch OpenAccount, to: OpenAccountHandler, aggregate: BankAccount, identity: :account_number
        end
      """
    end
  end

  defmodule MultiCommandRouter do
    use Commanded.Commands.Router

    dispatch [OpenAccount,CloseAccount], to: OpenAccountHandler, aggregate: BankAccount, identity: :account_number
  end

  test "should allow multiple module registrations for multiple commands in a single dispatch" do
    :ok = MultiCommandRouter.dispatch(%OpenAccount{account_number: "ACC123", initial_balance: 1_000})
    :ok = MultiCommandRouter.dispatch(%CloseAccount{account_number: "ACC123"})
  end

  defmodule MultiCommandHandlerRouter do
    use Commanded.Commands.Router

    dispatch [OpenAccount,CloseAccount], to: OpenAccountHandler, aggregate: BankAccount, identity: :account_number
    dispatch [DepositMoney], to: DepositMoneyHandler, aggregate: BankAccount, identity: :account_number
    dispatch [WithdrawMoney], to: WithdrawMoneyHandler, aggregate: BankAccount, identity: :account_number
  end

  test "should allow multiple module registrations for different command handlers" do
    :ok = MultiCommandHandlerRouter.dispatch(%OpenAccount{account_number: "ACC123", initial_balance: 1_000})
    :ok = MultiCommandHandlerRouter.dispatch(%DepositMoney{account_number: "ACC123", amount: 100})
  end

  test "should fail to dispatch command with nil identity" do
    {:error, :invalid_aggregate_identity} = ExampleRouter.dispatch(%OpenAccount{account_number: nil, initial_balance: 1_000})
  end
end
