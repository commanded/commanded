defmodule Commanded.ProcessManagers.ProcessManagerInstanceTest do
  use ExUnit.Case

  import Mox

  alias Commanded.Application.Config
  alias Commanded.Application.Mock, as: MockApplication
  alias Commanded.EventStore.Adapters.Mock, as: MockEventStore
  alias Commanded.EventStore.{RecordedEvent, SnapshotData}
  alias Commanded.ExampleDomain.BankAccount.Commands.WithdrawMoney
  alias Commanded.ExampleDomain.MoneyTransfer.Events.MoneyTransferRequested
  alias Commanded.ExampleDomain.TransferMoneyProcessManager
  alias Commanded.Helpers.Wait
  alias Commanded.ProcessManagers.IdentityProcessManager
  alias Commanded.ProcessManagers.IdentityProcessManager.AnEvent
  alias Commanded.ProcessManagers.{ProcessManagerInstance, ProcessRouter}
  alias Commanded.Registration.LocalRegistry
  alias Commanded.UUID

  setup :set_mox_global
  setup :verify_on_exit!

  setup do
    mock_event_store()

    {:ok, registry_meta} = start_local_registry()

    Config.associate(self(), MockApplication,
      application: MockApplication,
      event_store: {MockEventStore, %{}},
      registry: {LocalRegistry, registry_meta}
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
                 source_uuid: ^expected_source_uuid,
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

      event =
        to_recorded_event(%MoneyTransferRequested{
          transfer_uuid: transfer_uuid,
          debit_account: debit_account,
          credit_account: credit_account,
          amount: 100
        })

      :ok = ProcessManagerInstance.process_event(instance, event)

      # Should send ack to process router after processing event
      assert_receive({:"$gen_cast", {:ack_event, ^event, _instance}}, 1_000)
    end

    test "get current process identity" do
      {:ok, process_router} =
        start_supervised({IdentityProcessManager, application: MockApplication})

      process_uuids = Enum.sort([UUID.uuid4(), UUID.uuid4(), UUID.uuid4()])

      event = to_recorded_event(%AnEvent{uuids: process_uuids, reply_to: self()})

      send(process_router, {:events, [event]})

      process_instances =
        Wait.until(fn ->
          process_instances = ProcessRouter.process_instances(process_router)

          assert process_instances
                 |> Enum.map(fn {process_uuid, _pid} -> process_uuid end)
                 |> Enum.sort() == process_uuids

          process_instances
        end)

      for {process_uuid, pid} <- process_instances do
        assert_receive {:identity, ^process_uuid, ^pid}
      end
    end

    test "ignore unexpected messages" do
      import ExUnit.CaptureLog

      transfer_uuid = UUID.uuid4()

      expect(MockEventStore, :read_snapshot, fn _adapter_meta, _source_uuid ->
        {:error, :snapshot_not_found}
      end)

      {:ok, instance} = start_process_manager_instance(transfer_uuid)

      ref = Process.monitor(instance)

      send_unexpected_mesage = fn ->
        send(instance, :unexpected_message)

        refute_receive {:DOWN, ^ref, :process, ^instance, _}
      end

      assert capture_log(send_unexpected_mesage) =~
               "Commanded.ExampleDomain.TransferMoneyProcessManager received unexpected message: :unexpected_message"
    end

    defmodule NoAppProcessManager do
      use Commanded.ProcessManagers.ProcessManager, name: __MODULE__
    end

    test "should ensure a process manager application is provided" do
      expected_error =
        "Commanded.ProcessManagers.ProcessManagerInstanceTest.NoAppProcessManager expects :application option"

      assert_raise ArgumentError, expected_error, fn ->
        NoAppProcessManager.start_link()
      end
    end

    defmodule UnnamedProcessManager do
      use Commanded.ProcessManagers.ProcessManager, application: Commanded.DefaultApp
    end

    test "should ensure a process manager name is provided" do
      expected_error =
        "Commanded.ProcessManagers.ProcessManagerInstanceTest.UnnamedProcessManager expects :name option"

      assert_raise ArgumentError, expected_error, fn ->
        UnnamedProcessManager.start_link()
      end
    end

    defmodule MyProcessManager do
      use Commanded.ProcessManagers.ProcessManager,
        application: Commanded.DefaultApp,
        name: __MODULE__
    end

    test "should allow using process manager module as name" do
      start_supervised!(Commanded.DefaultApp)

      assert {:ok, _pid} = MyProcessManager.start_link()
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

  defp to_recorded_event(event) do
    %RecordedEvent{event_number: 1, stream_id: "stream-id", stream_version: 1, data: event}
  end

  defp mock_event_store do
    stub(MockEventStore, :subscribe_to, fn
      _event_store, :all, name, pid, :origin, _opts ->
        assert is_binary(name)
        assert is_pid(pid)

        send(pid, {:subscribed, self()})

        {:ok, self()}
    end)

    stub(MockEventStore, :read_snapshot, fn _event_store, _snapshot_uuid ->
      {:error, :snapshot_not_found}
    end)

    stub(MockEventStore, :record_snapshot, fn _event_store, _snapshot -> :ok end)
    stub(MockEventStore, :ack_event, fn _event_store, _pid, _event -> :ok end)
  end

  defp start_local_registry do
    {:ok, registry_child_spec, registry_meta} = LocalRegistry.child_spec(MockApplication, [])

    for child_spec <- registry_child_spec, do: start_supervised!(child_spec)

    {:ok, registry_meta}
  end
end
