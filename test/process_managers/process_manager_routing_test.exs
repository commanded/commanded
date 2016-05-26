defmodule Commanded.ProcessManager.ProcessManagerRoutingTest do
  use ExUnit.Case
  doctest Commanded.ProcessManagers.Router

  alias Commanded.ProcessManagers.Router
  alias Commanded.ExampleDomain.TransferMoneyProcessManager
  alias Commanded.ExampleDomain.{OpenAccountHandler,DepositMoneyHandler,TransferMoneyHandler,WithdrawMoneyHandler}
  alias Commanded.ExampleDomain.BankAccount.Commands.{OpenAccount,DepositMoney,WithdrawMoney}
  alias Commanded.ExampleDomain.MoneyTransfer.Commands.TransferMoney
  alias Commanded.Commands.{Dispatcher,Registry}

  setup do
    EventStore.Storage.reset!
    Commanded.Supervisor.start_link
    :ok = Registry.register(OpenAccount, OpenAccountHandler)
    :ok = Registry.register(DepositMoney, DepositMoneyHandler)
    :ok = Registry.register(WithdrawMoney, WithdrawMoneyHandler)
    :ok = Registry.register(TransferMoney, TransferMoneyHandler)
    :ok
  end

  @tag :wip
  test "start a process manager in response to an event" do
    account1_uuid = UUID.uuid4
    account2_uuid = UUID.uuid4

    {:ok, _} = Router.start_link("transfer_money_process_manager", TransferMoneyProcessManager)

    # create two bank accounts
    :ok = Dispatcher.dispatch(%OpenAccount{aggregate_uuid: account1_uuid, account_number: "ACC123", initial_balance: 1_000})
    :ok = Dispatcher.dispatch(%OpenAccount{aggregate_uuid: account2_uuid, account_number: "ACC456", initial_balance:  500})

    # transfer funds between account 1 and account 2
    :ok = Dispatcher.dispatch(%TransferMoney{source_account: account1_uuid, target_account: account2_uuid, amount: 100})

    EventStore.subscribe_to_all_streams("unit_test", self)

    assert_receive({:events, events})
    assert_receive({:events, events})
    assert_receive({:events, events})

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
