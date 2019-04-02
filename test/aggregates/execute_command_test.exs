defmodule Commanded.Aggregates.ExecuteCommandTest do
  use Commanded.StorageCase

  alias Commanded.Aggregates.{Aggregate, ExecutionContext}
  alias Commanded.ExampleDomain.{BankAccount, OpenAccountHandler}
  alias Commanded.ExampleDomain.BankAccount.Commands.OpenAccount
  alias Commanded.ExampleDomain.BankAccount.Events.BankAccountOpened
  alias Commanded.Helpers.{ProcessHelper, Wait}
  alias Commanded.Registration

  test "execute command against an aggregate" do
    account_number = UUID.uuid4()

    {:ok, ^account_number} = open_aggregate(BankAccount, account_number)

    command = %OpenAccount{account_number: account_number, initial_balance: 1_000}
    context = %ExecutionContext{command: command, handler: BankAccount, function: :open_account}

    {:ok, 1, events} = Aggregate.execute(BankAccount, account_number, context)

    assert events == [%BankAccountOpened{account_number: account_number, initial_balance: 1000}]

    ProcessHelper.shutdown_aggregate(BankAccount, account_number)

    # reload aggregate to fetch persisted events from event store and rebuild state by applying saved events
    {:ok, ^account_number} = open_aggregate(BankAccount, account_number)

    assert Aggregate.aggregate_version(BankAccount, account_number) == 1

    assert Aggregate.aggregate_state(BankAccount, account_number) == %BankAccount{
             account_number: account_number,
             balance: 1_000,
             state: :active
           }
  end

  test "execute command via a command handler" do
    account_number = UUID.uuid4()

    {:ok, ^account_number} = open_aggregate(BankAccount, account_number)

    command = %OpenAccount{account_number: account_number, initial_balance: 1_000}
    context = %ExecutionContext{command: command, handler: OpenAccountHandler, function: :handle}

    {:ok, 1, events} = Aggregate.execute(BankAccount, account_number, context)

    assert events == [%BankAccountOpened{account_number: account_number, initial_balance: 1000}]

    ProcessHelper.shutdown_aggregate(BankAccount, account_number)

    # reload aggregate to fetch persisted events from event store and rebuild state by applying saved events
    {:ok, ^account_number} = open_aggregate(BankAccount, account_number)

    assert Aggregate.aggregate_version(BankAccount, account_number) == 1

    assert Aggregate.aggregate_state(BankAccount, account_number) == %BankAccount{
             account_number: account_number,
             balance: 1_000,
             state: :active
           }
  end

  test "aggregate raising an exception should not persist pending events or state" do
    account_number = UUID.uuid4()

    {:ok, ^account_number} = open_aggregate(BankAccount, account_number)

    command = %OpenAccount{account_number: account_number, initial_balance: 1_000}
    context = %ExecutionContext{command: command, handler: OpenAccountHandler, function: :handle}

    {:ok, 1, _events} = Aggregate.execute(BankAccount, account_number, context)

    state_before = Aggregate.aggregate_state(BankAccount, account_number)

    assert_aggregate_exit(BankAccount, account_number, fn ->
      command = %OpenAccount{account_number: account_number, initial_balance: 1}

      context = %ExecutionContext{
        command: command,
        handler: OpenAccountHandler,
        function: :handle
      }

      Aggregate.execute(BankAccount, account_number, context)
    end)

    {:ok, ^account_number} = open_aggregate(BankAccount, account_number)

    assert state_before == Aggregate.aggregate_state(BankAccount, account_number)
  end

  describe "command dispatch return" do
    alias Commanded.Aggregates.ReturnValue.Command
    alias Commanded.Aggregates.ReturnValue.Event

    test "should allow `:ok` return value" do
      assert_no_events(fn %Command{} -> :ok end)
    end

    test "should allow `nil` return value" do
      assert_no_events(fn %Command{} -> nil end)
    end

    test "should allow `[]` return value" do
      assert_no_events(fn %Command{} -> [] end)
    end

    test "should allow single events return value" do
      assert_event_result(fn %Command{id: id} -> %Event{id: id} end)
    end

    test "should allow event list return value" do
      assert_event_result(fn %Command{id: id} -> [%Event{id: id}] end)
    end

    test "should allow `{:ok, event}` tagged tuple return value" do
      assert_event_result(fn %Command{id: id} -> {:ok, %Event{id: id}} end)
    end

    test "should allow `{:ok, event}` return value" do
      assert_event_result(fn %Command{id: id} -> {:ok, [%Event{id: id}]} end)
    end
  end

  defp assert_no_events(command_fun) do
    id = UUID.uuid4()

    assert {:ok, 0, []} = execute_aggregate_command(id, command_fun)
  end

  defp assert_event_result(command_fun) do
    alias Commanded.Aggregates.ReturnValue.Event

    id = UUID.uuid4()

    assert {:ok, 1, [%Event{id: ^id}]} = execute_aggregate_command(id, command_fun)
  end

  defp execute_aggregate_command(id, command_fun) do
    alias Commanded.Aggregates.ReturnValue.Command
    alias Commanded.Aggregates.ReturnValue.ExampleAggregate

    {:ok, ^id} = open_aggregate(ExampleAggregate, id)

    context = %ExecutionContext{
      command: %Command{id: id, fun: command_fun},
      handler: ExampleAggregate,
      function: :execute
    }

    Aggregate.execute(ExampleAggregate, id, context)
  end

  defp assert_aggregate_exit(aggregate_module, aggregate_uuid, fun) do
    pid = spawn(fun)

    # wait for spawned function to terminate
    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, _, _, _}

    # wait for aggregate process to terminate
    Wait.until(fn ->
      assert Registration.whereis_name({aggregate_module, aggregate_uuid}) == :undefined
    end)
  end

  defp open_aggregate(module, id) do
    Commanded.Aggregates.Supervisor.open_aggregate(module, id)
  end
end
