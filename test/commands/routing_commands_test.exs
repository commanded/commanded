defmodule Commanded.Commands.RoutingCommandsTest do
  use Commanded.StorageCase

  alias Commanded.DefaultApp
  alias Commanded.Commands.{ExecutionResult, UnregisteredCommand}
  alias Commanded.EventStore
  alias Commanded.ExampleDomain.BankAccount
  alias Commanded.ExampleDomain.{OpenAccountHandler, DepositMoneyHandler, WithdrawMoneyHandler}

  alias Commanded.ExampleDomain.BankAccount.Commands.{
    OpenAccount,
    CloseAccount,
    DepositMoney,
    WithdrawMoney
  }

  alias Commanded.ExampleDomain.BankAccount.Events.BankAccountOpened

  @dispatch_opts [application: DefaultApp]

  setup do
    start_supervised!(DefaultApp)

    :ok
  end

  describe "routing to command handler" do
    defmodule CommandHandlerRouter do
      use Commanded.Commands.Router

      dispatch OpenAccount,
        to: OpenAccountHandler,
        aggregate: BankAccount,
        identity: :account_number

      dispatch DepositMoney,
        to: DepositMoneyHandler,
        aggregate: BankAccount,
        identity: :account_number
    end

    test "should dispatch command to registered handler" do
      assert :ok =
               CommandHandlerRouter.dispatch(
                 %OpenAccount{
                   account_number: "ACC123",
                   initial_balance: 1_000
                 },
                 @dispatch_opts
               )
    end

    test "should fail to dispatch unregistered command" do
      assert {:error, :unregistered_command} =
               CommandHandlerRouter.dispatch(%UnregisteredCommand{}, @dispatch_opts)
    end

    test "should fail to dispatch command with `nil` identity" do
      assert {:error, :invalid_aggregate_identity} =
               CommandHandlerRouter.dispatch(
                 %OpenAccount{
                   account_number: nil,
                   initial_balance: 1_000
                 },
                 @dispatch_opts
               )
    end
  end

  describe "routing to aggregate" do
    alias Commanded.Commands.AggregateRouter
    alias Commanded.Commands.AggregateRoot.Command

    test "should dispatch command to registered handler" do
      assert :ok = AggregateRouter.dispatch(%Command{uuid: UUID.uuid4()}, @dispatch_opts)
    end

    test "should fail to dispatch unregistered command" do
      assert {:error, :unregistered_command} =
               AggregateRouter.dispatch(%UnregisteredCommand{}, @dispatch_opts)
    end
  end

  describe "identify aggregate prefix by string" do
    alias Commanded.Commands.IdentityAggregateRouter
    alias Commanded.Commands.IdentityAggregate.IdentityCommand

    test "should dispatch command to registered handler" do
      assert :ok =
               IdentityAggregateRouter.dispatch(
                 %IdentityCommand{uuid: UUID.uuid4()},
                 @dispatch_opts
               )
    end

    test "should append events to stream using identity prefix" do
      uuid = UUID.uuid4()
      assert :ok = IdentityAggregateRouter.dispatch(%IdentityCommand{uuid: uuid}, @dispatch_opts)

      recorded_events =
        EventStore.stream_forward(DefaultApp, "prefix-" <> uuid, 0) |> Enum.to_list()

      assert length(recorded_events) == 1
    end
  end

  describe "identify aggregate prefix by function" do
    alias Commanded.Commands.IdentityAggregatePrefixFunRouter
    alias Commanded.Commands.IdentityAggregate.IdentityCommand

    test "should dispatch command to registered handler" do
      assert :ok =
               IdentityAggregatePrefixFunRouter.dispatch(
                 %IdentityCommand{uuid: UUID.uuid4()},
                 @dispatch_opts
               )
    end

    test "should append events to stream using identity prefix" do
      uuid = UUID.uuid4()

      assert :ok =
               IdentityAggregatePrefixFunRouter.dispatch(
                 %IdentityCommand{uuid: uuid},
                 @dispatch_opts
               )

      recorded_events =
        EventStore.stream_forward(DefaultApp, "funprefix-" <> uuid, 0) |> Enum.to_list()

      assert length(recorded_events) == 1
    end
  end

  describe "identify aggregate using function" do
    alias Commanded.Commands.IdentityFunctionRouter
    alias Commanded.Commands.IdentityFunctionAggregate.IdentityFunctionCommand

    test "should dispatch command to registered handler" do
      assert :ok =
               IdentityFunctionRouter.dispatch(
                 %IdentityFunctionCommand{uuid: UUID.uuid4()},
                 @dispatch_opts
               )
    end

    test "should append events to stream" do
      uuid = UUID.uuid4()

      assert :ok =
               IdentityFunctionRouter.dispatch(
                 %IdentityFunctionCommand{uuid: uuid},
                 @dispatch_opts
               )

      recorded_events =
        EventStore.stream_forward(DefaultApp, "identityfun-" <> uuid, 0) |> Enum.to_list()

      assert length(recorded_events) == 1
    end
  end

  test "should ensure identity field is present" do
    assert_raise RuntimeError,
                 "Commanded.ExampleDomain.BankAccount aggregate identity is missing the `by` option",
                 fn ->
                   Code.eval_string("""
                     alias Commanded.ExampleDomain.BankAccount

                     defmodule DuplicateRouter do
                       use Commanded.Commands.Router

                       identify BankAccount, prefix: "account-"
                     end
                   """)
                 end
  end

  test "should prevent duplicate identity for an aggregate" do
    assert_raise RuntimeError,
                 "Commanded.ExampleDomain.BankAccount aggregate has already been identified by: `:account_number`",
                 fn ->
                   Code.eval_string("""
                     alias Commanded.ExampleDomain.BankAccount

                     defmodule DuplicateRouter do
                       use Commanded.Commands.Router

                       identify BankAccount, by: :account_number
                       identify BankAccount, by: :duplicate
                     end
                   """)
                 end
  end

  test "should prevent duplicate registrations for a command" do
    assert_raise ArgumentError,
                 "Command `Commanded.ExampleDomain.BankAccount.Commands.OpenAccount` has already been registered in router `DuplicateRouter`",
                 fn ->
                   Code.eval_string("""
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
                   """)
                 end
  end

  test "should prevent registration for a command handler without a `handle/2` function" do
    assert_raise ArgumentError,
                 "Command handler `InvalidHandler` does not define a `handle/2` function",
                 fn ->
                   Code.eval_string("""
                     alias Commanded.ExampleDomain.BankAccount
                     alias Commanded.ExampleDomain.BankAccount.Commands.OpenAccount

                     defmodule InvalidHandler do
                     end

                     defmodule InvalidRouter do
                       use Commanded.Commands.Router

                       dispatch OpenAccount, to: InvalidHandler, aggregate: BankAccount, identity: :account_number
                     end
                   """)
                 end
  end

  test "should show a helpful message when bad argument given to a `dispatch/2` function" do
    assert_raise RuntimeError,
                 """
                 unexpected dispatch parameter "id"
                 available params are: to, function, aggregate, identity, identity_prefix, timeout, lifespan, consistency
                 """,
                 fn ->
                   Code.eval_string("""
                     alias Commanded.ExampleDomain.BankAccount
                     alias Commanded.ExampleDomain.BankAccount.Commands.OpenAccount

                     defmodule InvalidRouter do
                       use Commanded.Commands.Router

                       dispatch OpenAccount, to: InvalidHandler, aggregate: BankAccount, id: :account_number
                     end
                   """)
                 end
  end

  test "should prevent registrations for a invalid command module" do
    assert_raise RuntimeError,
                 "module `UnknownCommand` does not exist, perhaps you forgot to `alias` the namespace",
                 fn ->
                   Code.eval_string("""
                     alias Commanded.ExampleDomain.BankAccount
                     alias Commanded.ExampleDomain.OpenAccountHandler

                     defmodule InvalidCommandRouter do
                       use Commanded.Commands.Router

                       dispatch UnknownCommand, to: OpenAccountHandler, aggregate: BankAccount, identity: :account_number
                     end
                   """)
                 end
  end

  test "should prevent registrations for an invalid command handler module" do
    assert_raise RuntimeError,
                 "module `UnknownHandler` does not exist, perhaps you forgot to `alias` the namespace",
                 fn ->
                   Code.eval_string("""
                     alias Commanded.ExampleDomain.BankAccount
                     alias Commanded.ExampleDomain.BankAccount.Commands.OpenAccount

                     defmodule InvalidHandlerRouter do
                       use Commanded.Commands.Router

                       dispatch OpenAccount, to: UnknownHandler, aggregate: BankAccount, identity: :account_number
                     end
                   """)
                 end
  end

  test "should prevent registrations for an invalid aggregate module" do
    assert_raise RuntimeError,
                 "module `UnknownAggregate` does not exist, perhaps you forgot to `alias` the namespace",
                 fn ->
                   Code.eval_string("""
                     alias Commanded.ExampleDomain.BankAccount.Commands.OpenAccount
                     alias Commanded.ExampleDomain.OpenAccountHandler

                     defmodule InvalidAggregateRouter do
                       use Commanded.Commands.Router

                       dispatch OpenAccount, to: OpenAccountHandler, aggregate: UnknownAggregate, identity: :account_number
                     end
                   """)
                 end
  end

  defmodule MultiCommandRouter do
    use Commanded.Commands.Router

    dispatch [OpenAccount, CloseAccount],
      to: OpenAccountHandler,
      aggregate: BankAccount,
      identity: :account_number
  end

  test "should allow multiple module registrations for multiple commands in a single dispatch" do
    assert :ok ==
             MultiCommandRouter.dispatch(
               %OpenAccount{
                 account_number: "ACC123",
                 initial_balance: 1_000
               },
               @dispatch_opts
             )

    assert :ok ==
             MultiCommandRouter.dispatch(%CloseAccount{account_number: "ACC123"}, @dispatch_opts)
  end

  defmodule MultiCommandHandlerRouter do
    use Commanded.Commands.Router

    dispatch [OpenAccount, CloseAccount],
      to: OpenAccountHandler,
      aggregate: BankAccount,
      identity: :account_number

    dispatch [DepositMoney],
      to: DepositMoneyHandler,
      aggregate: BankAccount,
      identity: :account_number

    dispatch [WithdrawMoney],
      to: WithdrawMoneyHandler,
      aggregate: BankAccount,
      identity: :account_number
  end

  test "should allow multiple module registrations for different command handlers" do
    assert :ok ==
             MultiCommandHandlerRouter.dispatch(
               %OpenAccount{
                 account_number: "ACC123",
                 initial_balance: 1_000
               },
               @dispatch_opts
             )

    assert :ok ==
             MultiCommandHandlerRouter.dispatch(
               %DepositMoney{
                 account_number: "ACC123",
                 amount: 100
               },
               @dispatch_opts
             )
  end

  describe "include aggregate version" do
    test "should return aggregate's updated stream version" do
      assert {:ok, 1} ==
               MultiCommandHandlerRouter.dispatch(
                 %OpenAccount{account_number: "ACC123", initial_balance: 1_000},
                 application: DefaultApp,
                 include_aggregate_version: true
               )

      assert {:ok, 2} ==
               MultiCommandHandlerRouter.dispatch(
                 %DepositMoney{account_number: "ACC123", amount: 100},
                 application: DefaultApp,
                 include_aggregate_version: true
               )
    end
  end

  test "should allow setting metadata" do
    metadata = %{"ip_address" => "127.0.0.1"}

    assert :ok ==
             MultiCommandHandlerRouter.dispatch(
               %OpenAccount{account_number: "ACC123", initial_balance: 1_000},
               application: DefaultApp,
               metadata: metadata
             )

    assert :ok ==
             MultiCommandHandlerRouter.dispatch(
               %DepositMoney{account_number: "ACC123", amount: 100},
               application: DefaultApp,
               metadata: metadata
             )

    events = EventStore.stream_forward(DefaultApp, "ACC123") |> Enum.to_list()
    assert length(events) == 2

    Enum.each(events, fn event ->
      assert event.metadata == metadata
    end)
  end

  describe "include execution result" do
    test "should return created events" do
      metadata = %{"ip_address" => "127.0.0.1"}
      command = %OpenAccount{account_number: "ACC123", initial_balance: 1_000}

      assert MultiCommandHandlerRouter.dispatch(command,
               application: DefaultApp,
               metadata: metadata,
               include_execution_result: true
             ) ==
               {
                 :ok,
                 %ExecutionResult{
                   aggregate_uuid: "ACC123",
                   aggregate_version: 1,
                   events: [%BankAccountOpened{account_number: "ACC123", initial_balance: 1000}],
                   metadata: metadata
                 }
               }
    end
  end
end
