defmodule Commanded.Aggregates.AggregateLifespanTest do
  use Commanded.StorageCase

  alias Commanded.Aggregates.{Aggregate, BankRouter}
  alias Commanded.ExampleDomain.BankAccount

  alias Commanded.ExampleDomain.BankAccount.Commands.{
    CloseAccount,
    OpenAccount,
    DepositMoney,
    WithdrawMoney
  }

  alias Commanded.ExampleDomain.BankAccount.Events.BankAccountOpened
  alias Commanded.EventStore
  alias Commanded.EventStore.RecordedEvent
  alias Commanded.Registration

  describe "aggregate started" do
    setup do
      aggregate_uuid = UUID.uuid4()

      {:ok, ^aggregate_uuid} =
        Commanded.Aggregates.Supervisor.open_aggregate(BankAccount, aggregate_uuid)

      pid = Registration.whereis_name({BankAccount, aggregate_uuid})
      ref = Process.monitor(pid)

      %{aggregate_uuid: aggregate_uuid, pid: pid, ref: ref}
    end

    test "should shutdown after timeout", %{aggregate_uuid: aggregate_uuid, ref: ref} do
      :ok = BankRouter.dispatch(%OpenAccount{account_number: aggregate_uuid, initial_balance: 10})

      assert_receive {:DOWN, ^ref, :process, _, :normal}
    end

    test "should not shutdown if another command executed", %{
      aggregate_uuid: aggregate_uuid,
      ref: ref
    } do
      :ok = BankRouter.dispatch(%OpenAccount{account_number: aggregate_uuid, initial_balance: 10})
      :ok = BankRouter.dispatch(%DepositMoney{account_number: aggregate_uuid, amount: 10})

      refute_receive {:DOWN, ^ref, :process, _, :normal}, 25
      assert_receive {:DOWN, ^ref, :process, _, :normal}
    end

    test "should use default lifespan when it's not specified'", %{
      aggregate_uuid: aggregate_uuid,
      ref: ref
    } do
      :ok = BankRouter.dispatch(%OpenAccount{account_number: aggregate_uuid, initial_balance: 10})
      :ok = BankRouter.dispatch(%WithdrawMoney{account_number: aggregate_uuid, amount: 10})

      refute_receive {:DOWN, ^ref, :process, _, :normal}, 100
    end

    test "should stop process when requested", %{
      aggregate_uuid: aggregate_uuid,
      ref: ref
    } do
      :ok = BankRouter.dispatch(%OpenAccount{account_number: aggregate_uuid, initial_balance: 10})
      :ok = BankRouter.dispatch(%CloseAccount{account_number: aggregate_uuid})

      assert_receive {:DOWN, ^ref, :process, _, :normal}
    end

    test "should adhere to aggregate lifespan when taking snapshot after receiving published event",
         %{
           aggregate_uuid: aggregate_uuid,
           pid: pid,
           ref: ref
         } do
      :ok = BankRouter.dispatch(%OpenAccount{account_number: aggregate_uuid, initial_balance: 10})

      events = aggregate_uuid |> EventStore.stream_forward() |> Enum.to_list()

      assert Process.alive?(pid)

      # publish events to aggregate before taking snapshot
      send(pid, {:events, events})

      :ok = Aggregate.take_snapshot(BankAccount, aggregate_uuid)

      assert_receive {:DOWN, ^ref, :process, _, :normal}
      assert {:ok, _snapshot} = EventStore.read_snapshot(aggregate_uuid)
    end

    test "should adhere to aggregate lifespan when receiving published events after taking snapshot",
         %{
           aggregate_uuid: aggregate_uuid,
           pid: pid,
           ref: ref
         } do
      :ok = BankRouter.dispatch(%OpenAccount{account_number: aggregate_uuid, initial_balance: 10})

      events = aggregate_uuid |> EventStore.stream_forward() |> Enum.to_list()

      :ok = Aggregate.take_snapshot(BankAccount, aggregate_uuid)

      assert Process.alive?(pid)

      # publish events to aggregate after taking snapshot
      send(pid, {:events, events})

      assert_receive {:DOWN, ^ref, :process, _, :normal}
      assert {:ok, _snapshot} = EventStore.read_snapshot(aggregate_uuid)
    end

    test "should use `:infinity` lifespan by default", %{
      aggregate_uuid: aggregate_uuid,
      pid: pid,
      ref: ref
    } do
      events = [
        %RecordedEvent{
          event_id: UUID.uuid4(),
          stream_version: 1,
          data: %BankAccountOpened{account_number: aggregate_uuid, initial_balance: 1_000}
        }
      ]

      # Simulate sending an event directly to the aggregate process
      send(pid, {:events, events})

      refute_receive {:DOWN, ^ref, :process, ^pid, _}
    end

    test "should adhere to aggregate lifespan after error", %{
      aggregate_uuid: aggregate_uuid,
      ref: ref
    } do
      ib = "clearly invalid"

      {:error, :invalid_initial_balance} =
        BankRouter.dispatch(%OpenAccount{account_number: aggregate_uuid, initial_balance: ib})

      refute_receive {:DOWN, ^ref, :process, _, :normal}, 29
      assert_receive {:DOWN, ^ref, :process, _, :normal}, 35
    end

    test "should adhere to timeout when no event returned", %{
      aggregate_uuid: aggregate_uuid,
      ref: ref
    } do
      :ok =
        BankRouter.dispatch(%OpenAccount{account_number: aggregate_uuid, initial_balance: 100})

      :ok = BankRouter.dispatch(%CloseAccount{account_number: aggregate_uuid})
      :ok = BankRouter.dispatch(%CloseAccount{account_number: aggregate_uuid})

      assert_receive {:DOWN, ^ref, :process, _, :normal}
    end
  end

  describe "deprecated `after_command/1` callback" do
    test "should fail to compile when missing `after_event/1` function" do
      assert_raise ArgumentError,
                   "Aggregate lifespan `BankAccountLifespan` does not define a callback function: `after_event/1`",
                   fn ->
                     Code.eval_string("""
                       alias Commanded.ExampleDomain.BankAccount
                       alias Commanded.ExampleDomain.BankAccount.Commands.{OpenAccount, DepositMoney}

                       defmodule BankAccountLifespan do
                         def after_command(%OpenAccount{}), do: 5
                         def after_command(%DepositMoney{}), do: 20
                         def after_command(_), do: :infinity
                       end

                       defmodule BankRouter do
                         use Commanded.Commands.Router

                         dispatch [OpenAccount],
                           to: BankAccount,
                           lifespan: BankAccountLifespan,
                           identity: :account_number
                       end
                     """)
                   end
    end
  end
end
