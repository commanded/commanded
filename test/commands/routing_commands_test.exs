defmodule Commanded.Commands.RoutingCommandsTest do
  use Commanded.StorageCase
  doctest Commanded.Commands.Router

  alias Commanded.ExampleDomain.BankAccount
  alias Commanded.ExampleDomain.{OpenAccountHandler,DepositMoneyHandler,WithdrawMoneyHandler}
  alias Commanded.ExampleDomain.BankAccount.Commands.{OpenAccount,CloseAccount,DepositMoney,WithdrawMoney}

  defmodule UnregisteredCommand, do: defstruct [aggregate_uuid: UUID.uuid4]

  describe "routing to command handler" do
    defmodule CommandHandlerRouter do
      use Commanded.Commands.Router

      dispatch OpenAccount, to: OpenAccountHandler, aggregate: BankAccount, identity: :account_number
      dispatch DepositMoney, to: DepositMoneyHandler, aggregate: BankAccount, identity: :account_number
    end

    test "should dispatch command to registered handler" do
      :ok = CommandHandlerRouter.dispatch(%OpenAccount{account_number: "ACC123", initial_balance: 1_000})
    end

    test "should fail to dispatch unregistered command" do
      {:error, :unregistered_command} = CommandHandlerRouter.dispatch(%UnregisteredCommand{})
    end

    test "should fail to dispatch command with nil identity" do
      {:error, :invalid_aggregate_identity} = CommandHandlerRouter.dispatch(%OpenAccount{account_number: nil, initial_balance: 1_000})
    end
  end

  describe "routing to aggregate" do
    defmodule Command, do: defstruct [uuid: nil]

    defmodule AggregateRoot do
      defstruct [uuid: nil]

      def execute(%AggregateRoot{}, %Command{}), do: []
    end

    defmodule AggregateRouter do
      use Commanded.Commands.Router

      dispatch Command, to: AggregateRoot, identity: :uuid
    end

    test "should dispatch command to registered handler" do
      :ok = AggregateRouter.dispatch(%Command{uuid: UUID.uuid4})
    end

    test "should fail to dispatch unregistered command" do
      {:error, :unregistered_command} = AggregateRouter.dispatch(%UnregisteredCommand{})
    end
  end

  test "should prevent duplicate registrations for a command" do
    # compile time safety net to prevent duplicate command registrations
    assert_raise RuntimeError, "duplicate command registration for: Commanded.ExampleDomain.BankAccount.Commands.OpenAccount", fn ->
      Code.eval_string """
        alias Commanded.ExampleDomain.BankAccount
        alias Commanded.ExampleDomain.BankAccount.Commands.OpenAccount

        defmodule Handler do
          def handle(%BankAccount{}, %OpenAccount{}), do: []
        end

        defmodule DuplicateRouter do
          use Commanded.Commands.Router

          dispatch OpenAccount, to: Handler, aggregate: BankAccount, identity: :account_number
          dispatch OpenAccount, to: Handler, aggregate: BankAccount, identity: :account_number
        end
      """
    end
  end

  test "should prevent registration for a command handler without a `handle/2` function" do
    # compile time safety net to prevent duplicate command registrations
    assert_raise RuntimeError, "command handler InvalidHandler does not define a function: handle/2", fn ->
      Code.eval_string """
        alias Commanded.ExampleDomain.BankAccount
        alias Commanded.ExampleDomain.BankAccount.Commands.OpenAccount

        defmodule InvalidHandler do
        end

        defmodule InvalidRouter do
          use Commanded.Commands.Router

          dispatch OpenAccount, to: InvalidHandler, aggregate: BankAccount, identity: :account_number
        end
      """
    end
  end

  test "should show a help note when bad argument given to a `dispatch/2` function" do
    assert_raise RuntimeError, """
    unexpected dispatch parameter "id"
    available params are: to, function, aggregate, identity, timeout
    """,
    fn ->
      Code.eval_string """
        alias Commanded.ExampleDomain.BankAccount
        alias Commanded.ExampleDomain.BankAccount.Commands.OpenAccount

        defmodule InvalidRouter do
          use Commanded.Commands.Router

          dispatch OpenAccount, to: InvalidHandler, aggregate: BankAccount, id: :account_number
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
end
