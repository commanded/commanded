defmodule Commanded.ProcessManager.ProcessManagerRoutingTest do
  use ExUnit.Case
  doctest Commanded.ProcessManagers.Router

  alias Commanded.ProcessManagers.Router
  alias Commanded.ExampleDomain.TransferMoneyProcessManager
  alias Commanded.ExampleDomain.{OpenAccountHandler,DepositMoneyHandler,TransferMoneyHandler,WithdrawMoneyHandler}
  alias Commanded.ExampleDomain.{BankAccount,MoneyTransfer}
  alias Commanded.ExampleDomain.BankAccount.Commands.{OpenAccount,DepositMoney,WithdrawMoney}
  alias Commanded.ExampleDomain.MoneyTransfer.Commands.TransferMoney

  setup do
    EventStore.Storage.reset!
    Commanded.Supervisor.start_link
    :ok
  end

  defmodule BankRouter do
    use Commanded.Commands.Router

    dispatch OpenAccount, to: OpenAccountHandler, aggregate: BankAccount, identity: :account_number
    dispatch DepositMoney, to: DepositMoneyHandler, aggregate: BankAccount, identity: :account_number
    dispatch WithdrawMoney, to: WithdrawMoneyHandler, aggregate: BankAccount, identity: :account_number
    dispatch TransferMoney, to: TransferMoneyHandler, aggregate: MoneyTransfer, identity: :transfer_uuid
  end

  test "should start a process manager in response to an event" do
    {:ok, _} = Router.start_link("transfer_money_process_manager", TransferMoneyProcessManager, BankRouter)

    # create two bank accounts
    :ok = BankRouter.dispatch(%OpenAccount{account_number: "ACC123", initial_balance: 1_000})
    :ok = BankRouter.dispatch(%OpenAccount{account_number: "ACC456", initial_balance:  500})

    # transfer funds between account 1 and account 2
    :ok = BankRouter.dispatch(%TransferMoney{source_account: "ACC123", target_account: "ACC456", amount: 100})

    EventStore.subscribe_to_all_streams("unit_test", self)

    assert_receive({:events, _events})
    assert_receive({:events, _events})
    assert_receive({:events, _events})

    receive do
      {:events, [recorded_event]} ->
        event = Commanded.Event.Serializer.map_from_recorded_event(recorded_event)

        assert event.amount == 100
        assert event.balance == 900
    after
      1_000 ->
        flunk("failed to receive expected event")
    end
  end
end
