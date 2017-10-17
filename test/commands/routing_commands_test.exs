defmodule Commanded.Commands.RoutingCommandsTest do
  use Commanded.StorageCase

  alias Commanded.EventStore
  alias Commanded.ExampleDomain.BankAccount
  alias Commanded.ExampleDomain.{OpenAccountHandler,DepositMoneyHandler,WithdrawMoneyHandler}
  alias Commanded.ExampleDomain.BankAccount.Commands.{OpenAccount,CloseAccount,DepositMoney,WithdrawMoney}
  alias Commanded.ExampleDomain.BankAccount.Events.BankAccountOpened
  alias Commanded.Commands.Dispatcher.ExecutionResult

  defmodule UnregisteredCommand, do: defstruct [aggregate_uuid: UUID.uuid4]

  describe "routing to command handler" do
    defmodule CommandHandlerRouter do
      use Commanded.Commands.Router

      dispatch OpenAccount, to: OpenAccountHandler, aggregate: BankAccount, identity: :account_number
      dispatch DepositMoney, to: DepositMoneyHandler, aggregate: BankAccount, identity: :account_number
    end

    test "should dispatch command to registered handler" do
      assert :ok = CommandHandlerRouter.dispatch(%OpenAccount{account_number: "ACC123", initial_balance: 1_000})
    end

    test "should fail to dispatch unregistered command" do
      assert {:error, :unregistered_command} = CommandHandlerRouter.dispatch(%UnregisteredCommand{})
    end

    test "should fail to dispatch command with nil identity" do
      assert {:error, :invalid_aggregate_identity} = CommandHandlerRouter.dispatch(%OpenAccount{account_number: nil, initial_balance: 1_000})
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
      assert :ok = AggregateRouter.dispatch(%Command{uuid: UUID.uuid4})
    end

    test "should fail to dispatch unregistered command" do
      assert {:error, :unregistered_command} = AggregateRouter.dispatch(%UnregisteredCommand{})
    end
  end

  describe "identify aggregate" do
    defmodule IdentityCommand, do: defstruct [:uuid]
    defmodule IdentityEvent, do: defstruct [:uuid]

    defmodule IdentityAggregateRoot do
      defstruct [uuid: nil]

      def execute(%__MODULE__{}, %IdentityCommand{uuid: uuid}), do: %IdentityEvent{uuid: uuid}
      def apply(aggregate, _event), do: aggregate
    end

    defmodule IdentityAggregateRouter do
      use Commanded.Commands.Router

      identify IdentityAggregateRoot,
        by: :uuid,
        prefix: "prefix-"

      dispatch IdentityCommand, to: IdentityAggregateRoot
    end

    test "should dispatch command to registered handler" do
      assert :ok = IdentityAggregateRouter.dispatch(%IdentityCommand{uuid: UUID.uuid4})
    end

    test "should append events to stream using identity prefix" do
      uuid = UUID.uuid4()
      assert :ok = IdentityAggregateRouter.dispatch(%IdentityCommand{uuid: uuid})

      recorded_events = EventStore.stream_forward("prefix-" <> uuid, 0) |> Enum.to_list()
      assert length(recorded_events) == 1
    end
  end

  describe "identify aggregate using function" do
    defmodule IdentityFunctionCommand, do: defstruct [:uuid]
    defmodule IdentityFunctionEvent, do: defstruct [:uuid]

    defmodule IdentityFunctionAggregateRoot do
      defstruct [uuid: nil]

      def execute(%__MODULE__{}, %IdentityFunctionCommand{uuid: uuid}), do: %IdentityFunctionEvent{uuid: uuid}
      def apply(aggregate, _event), do: aggregate
    end

    defmodule IdentityFunctionAggregateRouter do
      use Commanded.Commands.Router

      identify IdentityFunctionAggregateRoot,
        by: &IdentityFunctionAggregateRouter.aggregate_identity/1

      dispatch IdentityFunctionCommand, to: IdentityFunctionAggregateRoot

      def aggregate_identity(%{uuid: uuid}), do: "fun-prefix-" <> uuid
    end

    test "should dispatch command to registered handler" do
      assert :ok = IdentityFunctionAggregateRouter.dispatch(%IdentityFunctionCommand{uuid: UUID.uuid4})
    end

    test "should append events to stream" do
      uuid = UUID.uuid4()
      assert :ok = IdentityFunctionAggregateRouter.dispatch(%IdentityFunctionCommand{uuid: uuid})

      recorded_events = EventStore.stream_forward("fun-prefix-" <> uuid, 0) |> Enum.to_list()
      assert length(recorded_events) == 1
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
    available params are: to, function, aggregate, identity, identity_prefix, timeout, lifespan, consistency
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

  test "should prevent registrations for a invalid command module" do
    assert_raise RuntimeError, "module `UnknownCommand` does not exist, perhaps you forgot to `alias` the namespace", fn ->
      Code.eval_string """
        alias Commanded.ExampleDomain.BankAccount
        alias Commanded.ExampleDomain.OpenAccountHandler

        defmodule InvalidCommandRouter do
          use Commanded.Commands.Router

          dispatch UnknownCommand, to: OpenAccountHandler, aggregate: BankAccount, identity: :account_number
        end
      """
    end
  end

  test "should prevent registrations for an invalid command handler module" do
    assert_raise RuntimeError, "module `UnknownHandler` does not exist, perhaps you forgot to `alias` the namespace", fn ->
      Code.eval_string """
        alias Commanded.ExampleDomain.BankAccount
        alias Commanded.ExampleDomain.BankAccount.Commands.OpenAccount

        defmodule InvalidHandlerRouter do
          use Commanded.Commands.Router

          dispatch OpenAccount, to: UnknownHandler, aggregate: BankAccount, identity: :account_number
        end
      """
    end
  end

  test "should prevent registrations for an invalid aggregate module" do
    assert_raise RuntimeError, "module `UnknownAggregate` does not exist, perhaps you forgot to `alias` the namespace", fn ->
      Code.eval_string """
        alias Commanded.ExampleDomain.BankAccount.Commands.OpenAccount
        alias Commanded.ExampleDomain.OpenAccountHandler

        defmodule InvalidAggregateRouter do
          use Commanded.Commands.Router

          dispatch OpenAccount, to: OpenAccountHandler, aggregate: UnknownAggregate, identity: :account_number
        end
      """
    end
  end

  defmodule MultiCommandRouter do
    use Commanded.Commands.Router

    dispatch [OpenAccount,CloseAccount], to: OpenAccountHandler, aggregate: BankAccount, identity: :account_number
  end

  test "should allow multiple module registrations for multiple commands in a single dispatch" do
    assert :ok == MultiCommandRouter.dispatch(%OpenAccount{account_number: "ACC123", initial_balance: 1_000})
    assert :ok == MultiCommandRouter.dispatch(%CloseAccount{account_number: "ACC123"})
  end

  defmodule MultiCommandHandlerRouter do
    use Commanded.Commands.Router

    dispatch [OpenAccount,CloseAccount], to: OpenAccountHandler, aggregate: BankAccount, identity: :account_number
    dispatch [DepositMoney], to: DepositMoneyHandler, aggregate: BankAccount, identity: :account_number
    dispatch [WithdrawMoney], to: WithdrawMoneyHandler, aggregate: BankAccount, identity: :account_number
  end

  test "should allow multiple module registrations for different command handlers" do
    assert :ok == MultiCommandHandlerRouter.dispatch(%OpenAccount{account_number: "ACC123", initial_balance: 1_000})
    assert :ok == MultiCommandHandlerRouter.dispatch(%DepositMoney{account_number: "ACC123", amount: 100})
  end

  describe "include aggregate version" do
    test "should return aggregate's updated stream version" do
      assert {:ok, 1} == MultiCommandHandlerRouter.dispatch(%OpenAccount{account_number: "ACC123", initial_balance: 1_000}, include_aggregate_version: true)
      assert {:ok, 2} == MultiCommandHandlerRouter.dispatch(%DepositMoney{account_number: "ACC123", amount: 100}, include_aggregate_version: true)
    end
  end

  test "should allow setting metadata" do
    metadata = %{ip_address: "127.0.0.1"}

    assert :ok == MultiCommandHandlerRouter.dispatch(%OpenAccount{account_number: "ACC123", initial_balance: 1_000}, metadata: metadata)
    assert :ok == MultiCommandHandlerRouter.dispatch(%DepositMoney{account_number: "ACC123", amount: 100}, metadata: metadata)
  end

  describe "include execution result" do
    test "should return created events" do
      assert MultiCommandHandlerRouter.dispatch(%OpenAccount{account_number: "ACC123", initial_balance: 1_000}, include_execution_result: true) ==
        {
          :ok,
          %ExecutionResult{
            aggregate_uuid: "ACC123",
            aggregate_version: 1,
            events: [%BankAccountOpened{account_number: "ACC123", initial_balance: 1000}],
            metadata: nil
          }
        }
    end
  end
end
