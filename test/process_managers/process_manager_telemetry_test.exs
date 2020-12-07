defmodule Commanded.ProcessManagers.ProcessManagerTelemetryTest do
  use ExUnit.Case

  import Mox

  alias Commanded.Application.Config
  alias Commanded.Application.Mock, as: MockApplication
  alias Commanded.ExampleDomain.BankAccount.Commands.WithdrawMoney
  alias Commanded.ExampleDomain.MoneyTransfer.Events.MoneyTransferRequested
  alias Commanded.ExampleDomain.TransferMoneyProcessManager
  alias Commanded.EventStore.Adapters.Mock, as: MockEventStore
  alias Commanded.EventStore.SnapshotData
  alias Commanded.ProcessManagers.ProcessManagerInstance

  setup :set_mox_global
  setup :verify_on_exit!

  setup do
    Config.associate(self(), MockApplication,
      application: MockApplication,
      event_store: {MockEventStore, %{}}
    )

    attach_telemetry()

    :ok
  end

  @handler "test-pm-handler"

  # TODO change to a local example

  describe "process manager telemetry" do
    test "emit `[:commanded, :process_manager, :handle, :start]` event" do
      transfer_uuid = UUID.uuid4()
      debit_account = UUID.uuid4()
      credit_account = UUID.uuid4()
      expected_source_uuid = "\"TransferMoneyProcessManager\"-\"#{transfer_uuid}\""

      expect(MockEventStore, :read_snapshot, fn _adapter_meta, ^expected_source_uuid ->
        {:error, :snapshot_not_found}
      end)

      expect(MockEventStore, :record_snapshot, fn _adapter_meta, _snapshot -> :ok end)

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

      assert_receive({:"$gen_cast", _}, 1_000)
      assert_receive {[:commanded, :process_manager, :handle, :start], measurements, metadata}

      assert match?(%{system_time: _system_time}, measurements)

      assert match?(
               %{
                 application: Commanded.Application.Mock,
                 process_manager_module: Commanded.ExampleDomain.TransferMoneyProcessManager,
                 process_manager_name: "TransferMoneyProcessManager",
                 process_state: %Commanded.ExampleDomain.TransferMoneyProcessManager{},
                 process_uuid: ^transfer_uuid,
                 recorded_event: ^event
               },
               metadata
             )

      assert_receive {[:commanded, :process_manager, :handle, :stop], _measurements, _metadata}

      refute_receive {[:commanded, :process_manager, :handle, :exception], _measurements,
                      _metadata}
    end

    test "emit `[:commanded, :process_manager, :handle, :stop]` event" do
      transfer_uuid = UUID.uuid4()
      debit_account = UUID.uuid4()
      credit_account = UUID.uuid4()
      expected_source_uuid = "\"TransferMoneyProcessManager\"-\"#{transfer_uuid}\""

      expect(MockEventStore, :read_snapshot, fn _adapter_meta, ^expected_source_uuid ->
        {:error, :snapshot_not_found}
      end)

      expect(MockEventStore, :record_snapshot, fn _adapter_meta, _snapshot -> :ok end)

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

      assert_receive({:"$gen_cast", _}, 1_000)
      assert_receive {[:commanded, :process_manager, :handle, :start], _measurements, _metadata}

      assert_receive {[:commanded, :process_manager, :handle, :stop], measurements, metadata}

      assert match?(%{duration: _duration}, measurements)
      assert is_integer(measurements.duration)

      assert match?(
               %{
                 application: Commanded.Application.Mock,
                 process_manager_module: TransferMoneyProcessManager,
                 process_manager_name: "TransferMoneyProcessManager",
                 process_state: %TransferMoneyProcessManager{},
                 process_uuid: ^transfer_uuid,
                 recorded_event: ^event,
                 commands: [
                   %WithdrawMoney{}
                 ]
               },
               metadata
             )

      refute_receive {[:commanded, :process_manager, :handle, :exception], _measurements,
                      _metadata}
    end

    test "emit `[:commanded, :process_manager, :handle, :exception]` event" do
      transfer_uuid = UUID.uuid4()
      debit_account = UUID.uuid4()
      credit_account = UUID.uuid4()
      expected_source_uuid = "\"TransferMoneyProcessManager\"-\"#{transfer_uuid}\""

      expect(MockEventStore, :read_snapshot, fn _adapter_meta, ^expected_source_uuid ->
        {:error, :snapshot_not_found}
      end)

      expect(MockEventStore, :record_snapshot, fn _adapter_meta, _snapshot -> :ok end)

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

      assert_receive({:"$gen_cast", _}, 1_000)
      assert_receive {[:commanded, :process_manager, :handle, :start], _measurements, _metadata}

      refute_receive {[:commanded, :process_manager, :handle, :stop], _measurements, _metadata}

      assert_receive {[:commanded, :process_manager, :handle, :exception], _measurements,
                      _metadata}
    end
  end

  defp attach_telemetry do
    :telemetry.attach_many(
      @handler,
      [
        [:commanded, :process_manager, :handle, :start],
        [:commanded, :process_manager, :handle, :stop],
        [:commanded, :process_manager, :handle, :exception]
      ],
      fn event_name, measurements, metadata, reply_to ->
        send(reply_to, {event_name, measurements, metadata})
      end,
      self()
    )

    on_exit(fn ->
      :telemetry.detach(@handler)
    end)
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
    alias Commanded.EventStore.RecordedEvent

    %RecordedEvent{event_number: 1, stream_id: "stream-id", stream_version: 1, data: event}
  end
end
