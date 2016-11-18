defmodule Commanded.ProcessManager.ProcessManagerInstanceTest do
  use Commanded.StorageCase
  doctest Commanded.ProcessManagers.ProcessManagerInstance

  alias Commanded.ProcessManagers.ProcessManagerInstance
  alias Commanded.ExampleDomain.BankAccount
  alias Commanded.ExampleDomain.MoneyTransfer.Events.{MoneyTransferRequested}
  alias Commanded.ExampleDomain.BankAccount.Commands.WithdrawMoney
  alias Commanded.ExampleDomain.TransferMoneyProcessManager

  defmodule OpenAccountHandler do
    @behaviour Commanded.Commands.Handler

    def handle(%BankAccount{} = aggregate, %WithdrawMoney{}) do
      {:ok, aggregate}
    end
  end

  defmodule Router do
    use Commanded.Commands.Router

    dispatch WithdrawMoney, to: OpenAccountHandler, aggregate: BankAccount, identity: :account_number
  end

  test "process manager handles an event" do
    process_uuid = UUID.uuid4
    account1_uuid = UUID.uuid4
    account2_uuid = UUID.uuid4

    {:ok, process_manager} = ProcessManagerInstance.start_link(Router, "TransferMoneyProcessManager", TransferMoneyProcessManager, process_uuid)

    event = %EventStore.RecordedEvent{
      event_id: 1,
      data: %MoneyTransferRequested{
        transfer_uuid: process_uuid,
        debit_account: account1_uuid,
        credit_account: account2_uuid,
        amount: 100
      },
    }

    :ok = ProcessManagerInstance.process_event(process_manager, event, self)

    # should send ack to process router after processing event
    assert_receive({:"$gen_call", _, {:ack_event, 1}}, 1_000)
  end
end
