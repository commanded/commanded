defmodule Commanded.ProcessManagers.ProcessManagerInstanceTest do
  use ExUnit.Case

  import Mox

  alias Commanded.Application.Config
  alias Commanded.Application.Mock, as: MockApplication
  alias Commanded.ExampleDomain.BankAccount.Commands.WithdrawMoney
  alias Commanded.ExampleDomain.MoneyTransfer.Events.MoneyTransferRequested
  alias Commanded.ExampleDomain.TransferMoneyProcessManager
  alias Commanded.EventStore.Adapters.Mock, as: MockEventStore
  alias Commanded.EventStore.RecordedEvent
  alias Commanded.EventStore.SnapshotData
  alias Commanded.ProcessManagers.ProcessManagerInstance

  setup :set_mox_global
  setup :verify_on_exit!

  setup do
    Config.associate(self(), MockApplication,
      application: MockApplication,
      event_store: {MockEventStore, %{}}
    )
  end

  describe "process manager instance" do
    test "handles an event and dispatches a command" do
      transfer_uuid = UUID.uuid4()
      debit_account = UUID.uuid4()
      credit_account = UUID.uuid4()
      expected_source_uuid = "\"TransferMoneyProcessManager\"-\"#{transfer_uuid}\""

      expect(MockEventStore, :read_snapshot, fn _adapter_meta, ^expected_source_uuid ->
        {:error, :snapshot_not_found}
      end)

      expect(MockEventStore, :record_snapshot, fn _adapter_meta, snapshot ->
        assert %SnapshotData{
                 data: %TransferMoneyProcessManager{
                   amount: 100,
                   credit_account: ^credit_account,
                   debit_account: ^debit_account,
                   status: :withdraw_money_from_debit_account,
                   transfer_uuid: ^transfer_uuid
                 },
                 source_type: "Elixir.Commanded.ExampleDomain.TransferMoneyProcessManager",
                 source_uuid: expected_source_uuid,
                 source_version: 1
               } = snapshot

        :ok
      end)

      expect(MockApplication, :dispatch, fn command, _opts ->
        assert %WithdrawMoney{
                 account_number: ^debit_account,
                 transfer_uuid: ^transfer_uuid,
                 amount: 100
               } = command

        :ok
      end)

      {:ok, instance} = start_process_manager_instance(transfer_uuid)

      event = %RecordedEvent{
        event_number: 1,
        stream_id: "stream-id",
        stream_version: 1,
        data: %MoneyTransferRequested{
          transfer_uuid: transfer_uuid,
          debit_account: debit_account,
          credit_account: credit_account,
          amount: 100
        }
      }

      :ok = ProcessManagerInstance.process_event(instance, event)

      # Should send ack to process router after processing event
      assert_receive({:"$gen_cast", {:ack_event, ^event, _instance}}, 1_000)
    end

    test "ignore unexpected messages" do
      transfer_uuid = UUID.uuid4()

      expect(MockEventStore, :read_snapshot, fn _adapter_meta, _source_uuid ->
        {:error, :snapshot_not_found}
      end)

      {:ok, instance} = start_process_manager_instance(transfer_uuid)

      ref = Process.monitor(instance)

      send(instance, :unexpected_message)

      refute_receive {:DOWN, ^ref, :process, ^instance, _}
    end

    test "should provide `__name__/0` function" do
      assert TransferMoneyProcessManager.__name__() ==
               "Commanded.ExampleDomain.TransferMoneyProcessManager"
    end

    test "should ensure a process manager application is provided" do
      assert_raise ArgumentError, "NoAppProcessManager expects :application option", fn ->
        Code.eval_string("""
          defmodule NoAppProcessManager do
            use Commanded.ProcessManagers.ProcessManager, name: __MODULE__
          end
        """)
      end
    end

    test "should ensure a process manager name is provided" do
      assert_raise ArgumentError, "UnnamedProcessManager expects :name option", fn ->
        Code.eval_string("""
          defmodule UnnamedProcessManager do
            use Commanded.ProcessManagers.ProcessManager, application: Commanded.DefaultApp
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

  defp start_process_manager_instance(transfer_uuid) do
    start_supervised(
      {ProcessManagerInstance,
       application: MockApplication,
       idle_timeout: :infinity,
       process_manager_name: "TransferMoneyProcessManager",
       process_manager_module: TransferMoneyProcessManager,
       process_router: self(),
       process_uuid: transfer_uuid}
    )
  end
end
