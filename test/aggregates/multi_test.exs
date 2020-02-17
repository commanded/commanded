defmodule Commanded.Aggregate.MultiTest do
  use ExUnit.Case

  import Commanded.Enumerable

  alias Commanded.DefaultApp
  alias Commanded.EventStore
  alias Commanded.Aggregate.Multi
  alias Commanded.Aggregate.Multi.BankAccount
  alias Commanded.Aggregate.Multi.BankAccount.Commands.{OpenAccount, WithdrawMoney}
  alias Commanded.Aggregate.Multi.BankAccount.Events.{BankAccountOpened, MoneyWithdrawn}
  alias Commanded.Aggregate.MultiBankRouter

  setup do
    start_supervised!(DefaultApp)
    :ok
  end

  test "should return `Commanded.Aggregate.Multi` from command" do
    account_number = UUID.uuid4()

    account =
      BankAccount.apply(%BankAccount{}, %BankAccountOpened{
        account_number: account_number,
        balance: 1_000
      })

    assert %Multi{} =
             multi =
             BankAccount.execute(account, %WithdrawMoney{
               account_number: account_number,
               amount: 100
             })

    assert {account, events} = Multi.run(multi)

    assert account == %BankAccount{
             account_number: account_number,
             balance: 900,
             status: :active
           }

    assert events == [
             %MoneyWithdrawn{account_number: account_number, amount: 100, balance: 900}
           ]
  end

  test "should return errors encountered by `Commanded.Aggregate.Multi`" do
    account_number = UUID.uuid4()

    account =
      BankAccount.apply(%BankAccount{}, %BankAccountOpened{
        account_number: account_number,
        balance: 1_000
      })

    assert %Multi{} =
             multi =
             BankAccount.execute(account, %WithdrawMoney{
               account_number: account_number,
               amount: 1_100
             })

    assert {:error, :insufficient_funds_available} = Multi.run(multi)
  end

  test "should execute command using `Commanded.Aggregate.Multi` and return events" do
    account_number = UUID.uuid4()

    command = %OpenAccount{account_number: account_number, initial_balance: 1_000}
    assert :ok = MultiBankRouter.dispatch(command, application: DefaultApp)

    command = %WithdrawMoney{account_number: account_number, amount: 250}
    assert :ok = MultiBankRouter.dispatch(command, application: DefaultApp)

    recorded_events = EventStore.stream_forward(DefaultApp, account_number, 0) |> Enum.to_list()

    assert pluck(recorded_events, :data) == [
             %BankAccountOpened{account_number: account_number, balance: 1_000},
             %MoneyWithdrawn{account_number: account_number, amount: 250, balance: 750}
           ]
  end

  test "should execute command using `Commanded.Aggregate.Multi` and return any error" do
    account_number = UUID.uuid4()

    command = %OpenAccount{account_number: account_number, initial_balance: 1_000}
    assert :ok = MultiBankRouter.dispatch(command, application: DefaultApp)

    command = %WithdrawMoney{account_number: account_number, amount: 1_100}

    assert {:error, :insufficient_funds_available} =
             MultiBankRouter.dispatch(command, application: DefaultApp)

    recorded_events = EventStore.stream_forward(DefaultApp, account_number, 0) |> Enum.to_list()

    assert pluck(recorded_events, :data) == [
             %BankAccountOpened{account_number: account_number, balance: 1_000}
           ]
  end

  describe "nested `Commanded.Aggregate.Multi`" do
    defmodule ExampleAggregate do
      defstruct events: []

      defmodule Event do
        defstruct [:data]
      end

      def apply(%ExampleAggregate{} = aggregate, event) do
        %ExampleAggregate{events: events} = aggregate

        %ExampleAggregate{aggregate | events: events ++ [event]}
      end
    end

    alias ExampleAggregate.Event

    test "should be supported" do
      {%ExampleAggregate{}, events} =
        %ExampleAggregate{}
        |> Multi.new()
        |> Multi.execute(fn %ExampleAggregate{} = aggregate ->
          aggregate
          |> Multi.new()
          |> Multi.execute(fn %ExampleAggregate{events: events} ->
            assert length(events) == 0

            %Event{data: 1}
          end)
        end)
        |> Multi.execute(fn %ExampleAggregate{events: events} ->
          assert length(events) == 1

          %Event{data: 2}
        end)
        |> Multi.execute(fn %ExampleAggregate{events: events} ->
          assert length(events) == 2

          []
        end)
        |> Multi.run()

      assert events == [%Event{data: 1}, %Event{data: 2}]
    end

    test "should reduce enum" do
      {%ExampleAggregate{}, events} =
        %ExampleAggregate{}
        |> Multi.new()
        |> Multi.reduce([1, 2, 3], fn %ExampleAggregate{events: events}, index ->
          assert length(events) == index - 1

          %Event{data: index}
        end)
        |> Multi.run()

      assert events == [%Event{data: 1}, %Event{data: 2}, %Event{data: 3}]
    end
  end
end
