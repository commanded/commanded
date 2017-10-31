defmodule Commanded.Commands.CorrelationCasuationTest do
  use Commanded.StorageCase

  import Commanded.Assertions.EventAssertions

  alias Commanded.EventStore
  alias Commanded.ExampleDomain.{
    BankRouter,
    TransferMoneyProcessManager,
  }
  alias Commanded.ExampleDomain.BankAccount.Commands.{
    OpenAccount,
    WithdrawMoney,
  }
  alias Commanded.ExampleDomain.BankAccount.Events.{
    MoneyDeposited,
  }
  alias Commanded.ExampleDomain.MoneyTransfer.Commands.TransferMoney
  alias Commanded.Helpers.CommandAuditMiddleware

  setup do
    CommandAuditMiddleware.reset()
    {:ok, process_manager} = TransferMoneyProcessManager.start_link()

    on_exit fn ->
      Commanded.Helpers.Process.shutdown(process_manager)
    end
  end

  describe "`causation_id`" do
    test "should be copied to dispatched command" do
      causation_id = UUID.uuid4()
      open_account = %OpenAccount{account_number: "ACC123", initial_balance: 500}

      :ok = BankRouter.dispatch(open_account, causation_id: causation_id)

      # a command's `causation_id` is set by the value passed to command dispatch
      assert [^causation_id] = CommandAuditMiddleware.dispatched_commands(&(&1.causation_id))
    end

    test "should be set from `command_uuid` on created event" do
      :ok = BankRouter.dispatch(%OpenAccount{account_number: "ACC123", initial_balance: 500})

      [command_uuid] = CommandAuditMiddleware.dispatched_commands(&(&1.command_uuid))
      [event] = EventStore.stream_forward("ACC123") |> Enum.to_list()

      # an event's `causation_id` is the dispatched command's `command_uuid`
      assert event.causation_id == command_uuid
    end

    test "should be copied onto commands/events by process manager" do
      transfer_uuid = UUID.uuid4()

      :ok = BankRouter.dispatch(%OpenAccount{account_number: "ACC123", initial_balance: 500})
      :ok = BankRouter.dispatch(%OpenAccount{account_number: "ACC456", initial_balance: 100})

      CommandAuditMiddleware.reset()

      :ok = BankRouter.dispatch(%TransferMoney{transfer_uuid: transfer_uuid, debit_account: "ACC123", credit_account: "ACC456", amount: 100})

      assert_receive_event MoneyDeposited, fn event -> assert event.transfer_uuid == transfer_uuid end

      # withdraw money command's `causation_id` should be money transfer requested event's id
      transfer_requested = EventStore.stream_forward(transfer_uuid) |> Enum.at(0)
      [_, causation_id, _] = CommandAuditMiddleware.dispatched_commands(&(&1.causation_id))
      assert causation_id == transfer_requested.event_id
    end
  end

  describe "`correlation_id`" do
    test "should be copied to dispatched command" do
      correlation_id = UUID.uuid4()

      :ok = BankRouter.dispatch(%OpenAccount{account_number: "ACC123", initial_balance: 500}, correlation_id: correlation_id)

      assert [^correlation_id] = CommandAuditMiddleware.dispatched_commands(&(&1.correlation_id))
    end

    test "should be set on all created events" do
      correlation_id = UUID.uuid4()

      :ok = BankRouter.dispatch(%OpenAccount{account_number: "ACC123", initial_balance: 500}, correlation_id: correlation_id)
      :ok = BankRouter.dispatch(%WithdrawMoney{account_number: "ACC123", amount: 1_000}, correlation_id: correlation_id)

      events = EventStore.stream_forward("ACC123") |> Enum.to_list()
      assert length(events) == 3

      for event <- events do
        assert event.correlation_id == correlation_id
      end
    end

    test "should be copied onto commands/events by process manager" do
      correlation_id = UUID.uuid4()
      transfer_uuid = UUID.uuid4()

      :ok = BankRouter.dispatch(%OpenAccount{account_number: "ACC123", initial_balance: 500})
      :ok = BankRouter.dispatch(%OpenAccount{account_number: "ACC456", initial_balance: 100})

      CommandAuditMiddleware.reset()

      :ok = BankRouter.dispatch(%TransferMoney{transfer_uuid: transfer_uuid, debit_account: "ACC123", credit_account: "ACC456", amount: 100}, correlation_id: correlation_id)

      assert_receive_event MoneyDeposited, fn event -> assert event.transfer_uuid == transfer_uuid end

      # `correlation_id` should be the same for all commands & events related to money transfer
      assert [correlation_id, correlation_id, correlation_id] =
        CommandAuditMiddleware.dispatched_commands(&(&1.correlation_id))

      event = EventStore.stream_forward(transfer_uuid) |> Enum.at(0)
      assert event.correlation_id == correlation_id
    end
  end
end
