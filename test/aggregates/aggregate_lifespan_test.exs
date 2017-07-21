defmodule Commanded.Aggregates.AggregateLifespanTest do
  use Commanded.StorageCase
  use Commanded.EventStore

  alias Commanded.ExampleDomain.BankAccount

  alias Commanded.ExampleDomain.BankAccount.Commands.{
    OpenAccount,
    DepositMoney,
    WithdrawMoney,
  }
  alias Commanded.ExampleDomain.{
    OpenAccountHandler,
    DepositMoneyHandler,
    WithdrawMoneyHandler,
  }

  defmodule BankAccountLifespan do
    @behaviour Commanded.Aggregates.AggregateLifespan

    def after_command(%OpenAccount{}), do: 5
    def after_command(%DepositMoney{}), do: 20
  end

  defmodule BankRouter do
    use Commanded.Commands.Router

    dispatch OpenAccount, to: OpenAccountHandler, aggregate: BankAccount, lifespan: BankAccountLifespan, identity: :account_number
    dispatch DepositMoney, to: DepositMoneyHandler, aggregate: BankAccount, lifespan: BankAccountLifespan, identity: :account_number
    dispatch WithdrawMoney, to: WithdrawMoneyHandler, aggregate: BankAccount, identity: :account_number
  end

  describe "aggregate started" do
    setup do
      aggregate_uuid = UUID.uuid4

      {:ok, ^aggregate_uuid} = Commanded.Aggregates.Supervisor.open_aggregate(BankAccount, aggregate_uuid)

      #[{pid, _}] = Registry.lookup(:aggregate_registry, aggregate_uuid)
      pid = Swarm.whereis_name(aggregate_uuid)
      ref = Process.monitor(pid)

      %{aggregate_uuid: aggregate_uuid, ref: ref}
    end

    test "should shutdown after timeout", %{aggregate_uuid: aggregate_uuid, ref: ref} do
      :ok = BankRouter.dispatch(%OpenAccount{account_number: aggregate_uuid, initial_balance: 10})

      assert_receive {:DOWN, ^ref, :process, _, :normal}, 10
    end

    test "should not shutdown if next command executed", %{aggregate_uuid: aggregate_uuid, ref: ref} do
      :ok = BankRouter.dispatch(%OpenAccount{account_number: aggregate_uuid, initial_balance: 10})
      :ok = BankRouter.dispatch(%DepositMoney{account_number: aggregate_uuid, amount: 10})

      refute_receive {:DOWN, ^ref, :process, _, :normal}, 10
      assert_receive {:DOWN, ^ref, :process, _, :normal}, 30
    end

    test "should use default lifespan when it's not specified'", %{aggregate_uuid: aggregate_uuid, ref: ref} do
      :ok = BankRouter.dispatch(%OpenAccount{account_number: aggregate_uuid, initial_balance: 10})
      :ok = BankRouter.dispatch(%WithdrawMoney{account_number: aggregate_uuid, amount: 10})

      refute_receive {:DOWN, ^ref, :process, _, :normal}, 30
    end
  end
end
