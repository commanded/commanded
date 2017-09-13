defmodule Commanded.ProcessManager.ProcessManagerInstanceTest do
  use Commanded.StorageCase
  doctest Commanded.ProcessManagers.ProcessManagerInstance

  alias Commanded.ExampleDomain.BankAccount
  alias Commanded.ExampleDomain.BankAccount.Commands.WithdrawMoney
  alias Commanded.ExampleDomain.MoneyTransfer.Events.MoneyTransferRequested
  alias Commanded.ExampleDomain.TransferMoneyProcessManager
  alias Commanded.EventStore.RecordedEvent
  alias Commanded.ProcessManagers.ProcessManagerInstance

  defmodule NullHandler do
    @behaviour Commanded.Commands.Handler

    def handle(_aggregate, _command), do: []
  end

  defmodule Router do
    use Commanded.Commands.Router

    dispatch WithdrawMoney, to: NullHandler, aggregate: BankAccount, identity: :account_number
  end

  test "process manager handles an event" do
    transfer_uuid = UUID.uuid4
    account1_uuid = UUID.uuid4
    account2_uuid = UUID.uuid4

    {:ok, process_manager} = ProcessManagerInstance.start_link(Router, "TransferMoneyProcessManager", TransferMoneyProcessManager, transfer_uuid)

    event = %RecordedEvent{
      event_number: 1,
      stream_id: "stream-id",
      stream_version: 1,
      data: %MoneyTransferRequested{
        transfer_uuid: transfer_uuid,
        debit_account: account1_uuid,
        credit_account: account2_uuid,
        amount: 100,
      },
    }

    :ok = ProcessManagerInstance.process_event(process_manager, event, self())

    # should send ack to process router after processing event
    assert_receive({:"$gen_cast", {:ack_event, ^event}}, 1_000)
  end

  test "should ensure a process manager name is provided" do
    assert_raise RuntimeError, "UnnamedProcessManager expects `:name` to be given", fn ->
      Code.eval_string """
        defmodule UnnamedProcessManager do
          use Commanded.ProcessManagers.ProcessManager,
            router: Commanded.ExampleDomain.BankRouter
        end
      """
    end
  end

  test "should ensure a process manager router is provided" do
    assert_raise RuntimeError, "NoRouterProcessManager expects `:router` to be given", fn ->
      Code.eval_string """
        defmodule NoRouterProcessManager do
          use Commanded.ProcessManagers.ProcessManager,
            name: "MyProcessManager"
        end
      """
    end
  end

  test "should allow using process manager module as name" do
    Code.eval_string """
      defmodule MyProcessManager do
        use Commanded.ProcessManagers.ProcessManager,
          name: __MODULE__,
          router: Commanded.ExampleDomain.BankRouter
      end
    """
  end
end
