defmodule Commanded.Commands.RoutingCommandsTest do
  use ExUnit.Case
  doctest Commanded.Commands.Router

  import Commanded.Helpers.CompileTimeAssertions

  alias Commanded.Commands
  alias Commanded.Commands.Router
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

  setup do
    EventStore.Storage.reset!
    Commanded.Supervisor.start_link
    :ok
  end

  test "dispatch command to registered handler" do
    :ok = ExampleRouter.dispatch(%OpenAccount{account_number: "ACC123", initial_balance: 1_000})
  end

  test "should fail to dispatch unregistered command" do
    {:error, :unregistered_command} = ExampleRouter.dispatch(%UnregisteredCommand{})
  end

  test "don't allow duplicate registrations for a command" do
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

  # test "should fail to dispatch command without an `aggregate_uuid` field"
  # test "should fail to dispatch command with nil `aggregate_uuid`"
end
