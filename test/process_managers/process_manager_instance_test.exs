defmodule Commanded.ProcessManagers.ProcessManagerInstanceTest do
  use Commanded.StorageCase

  alias Commanded.ExampleDomain.MoneyTransfer.Events.MoneyTransferRequested
  alias Commanded.ExampleDomain.TransferMoneyProcessManager
  alias Commanded.EventStore.RecordedEvent
  alias Commanded.ProcessManagers.{ProcessManagerInstance, NullRouter}
  alias Commanded.Helpers.ProcessHelper

  test "process manager handles an event" do
    transfer_uuid = UUID.uuid4()
    account1_uuid = UUID.uuid4()
    account2_uuid = UUID.uuid4()

    {:ok, process_manager} =
      ProcessManagerInstance.start_link(
        command_dispatcher: NullRouter,
        idle_timeout: :infinity,
        process_manager_name: "TransferMoneyProcessManager",
        process_manager_module: TransferMoneyProcessManager,
        process_router: self(),
        process_uuid: transfer_uuid
      )

    event = %RecordedEvent{
      event_number: 1,
      stream_id: "stream-id",
      stream_version: 1,
      data: %MoneyTransferRequested{
        transfer_uuid: transfer_uuid,
        debit_account: account1_uuid,
        credit_account: account2_uuid,
        amount: 100
      }
    }

    :ok = ProcessManagerInstance.process_event(process_manager, event)

    # Should send ack to process router after processing event
    assert_receive({:"$gen_cast", {:ack_event, ^event, _instance}}, 1_000)

    ProcessHelper.shutdown(process_manager)
  end

  test "should provide `__name__/0` function" do
    assert TransferMoneyProcessManager.__name__() ==
             "Commanded.ExampleDomain.TransferMoneyProcessManager"
  end

  test "should ensure a process manager application is provided" do
    assert_raise RuntimeError, "UnnamedProcessManager expects `:name` to be given", fn ->
      Code.eval_string("""
        defmodule UnnamedProcessManager do
          use Commanded.ProcessManagers.ProcessManager, name: __MODULE__
        end
      """)
    end
  end

  test "should ensure a process manager name is provided" do
    assert_raise RuntimeError, "UnnamedProcessManager expects `:name` to be given", fn ->
      Code.eval_string("""
        defmodule UnnamedProcessManager do
          use Commanded.ProcessManagers.ProcessManager,
            application: Commanded.DefaultApp
        end
      """)
    end
  end

  test "should allow using process manager module as name" do
    Code.eval_string("""
      defmodule MyProcessManager do
        use Commanded.ProcessManagers.ProcessManager,
          application: Commanded.DefaultApp,
          name: __MODULE__
      end
    """)
  end
end
