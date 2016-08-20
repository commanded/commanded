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
    account_number1 = UUID.uuid4
    account_number2 = UUID.uuid4

    {:ok, _} = Router.start_link("transfer_money_process_manager", TransferMoneyProcessManager, BankRouter)

    # create two bank accounts
    :ok = BankRouter.dispatch(%OpenAccount{account_number: account_number1, initial_balance: 1_000})
    :ok = BankRouter.dispatch(%OpenAccount{account_number: account_number2, initial_balance:  500})

    # transfer funds between account 1 and account 2
    :ok = BankRouter.dispatch(%TransferMoney{source_account: account_number1, target_account: account_number2, amount: 100})

    EventStore.subscribe_to_all_streams("unit_test", self)

    assert_receive({:events, _events}, 1_000)
    assert_receive({:events, _events}, 1_000)
    assert_receive({:events, _events}, 1_000)

    receive do
      {:events, [recorded_event]} ->
        event = Commanded.Event.Mapper.map_from_recorded_event(recorded_event)

        assert event.amount == 100
        assert event.balance == 900
    after
      1_000 ->
        flunk("failed to receive expected event")
    end
  end
end
