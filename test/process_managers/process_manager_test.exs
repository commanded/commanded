defmodule Commanded.ProcessManager.ProcessManagerTest do
  use ExUnit.Case
  doctest Commanded.ProcessManagers.ProcessManager

  alias Commanded.ProcessManagers.ProcessManager
  alias Commanded.ExampleDomain.MoneyTransfer.Events.{MoneyTransferRequested}
  alias Commanded.ExampleDomain.TransferMoneyProcessManager
  alias Commanded.Helpers

  test "process manager handles an event" do
    process_uuid = UUID.uuid4
    account1_uuid = UUID.uuid4
    account2_uuid = UUID.uuid4

    {:ok, process_manager} = ProcessManager.start_link(TransferMoneyProcessManager, process_uuid)

    event = %MoneyTransferRequested{
      transfer_uuid: process_uuid,
      source_account: account1_uuid,
      target_account: account2_uuid,
      amount: 100
    }

    :ok = ProcessManager.process_event(process_manager, event)
  end
end
