defmodule Commanded.Commands.CorrelationCasuationTest do
  use Commanded.StorageCase

  alias Commanded.EventStore
  alias Commanded.ExampleDomain.{
    BankAccount,
    OpenAccountHandler,
    DepositMoneyHandler,
    WithdrawMoneyHandler,
  }
  alias BankAccount.Commands.{
    OpenAccount,
    DepositMoney,
    WithdrawMoney,
  }
  alias Commanded.Helpers.CommandAuditMiddleware

  defmodule AuditedBankRouter do
    use Commanded.Commands.Router

    middleware CommandAuditMiddleware

    identify BankAccount, by: :account_number

    dispatch OpenAccount, to: OpenAccountHandler, aggregate: BankAccount
    dispatch DepositMoney, to: DepositMoneyHandler, aggregate: BankAccount
    dispatch WithdrawMoney, to: WithdrawMoneyHandler, aggregate: BankAccount
  end

  setup do
    {:ok, middleware} = CommandAuditMiddleware.start_link()

    on_exit fn ->
      Commanded.Helpers.Process.shutdown(middleware)
    end
  end

  describe "`causation_id`" do
    test "should be copied to dispatched command" do
      causation_id = UUID.uuid4()
      open_account = %OpenAccount{account_number: "ACC123", initial_balance: 500}

      :ok = AuditedBankRouter.dispatch(open_account, causation_id: causation_id)

      # a command's `causation_id` is set by the value passed to command dispatch
      assert [^causation_id] = CommandAuditMiddleware.dispatched_commands(&(&1.causation_id))
    end

    test "should be set from `command_uuid` on created event" do
      :ok = AuditedBankRouter.dispatch(%OpenAccount{account_number: "ACC123", initial_balance: 500})

      [command_uuid] = CommandAuditMiddleware.dispatched_commands(&(&1.command_uuid))
      [event] = EventStore.stream_forward("ACC123") |> Enum.to_list()

      # an event's `causation_id` is the dispatched command's `command_uuid`
      assert event.causation_id == command_uuid
    end
  end

  describe "`correlation_id`" do
    test "should be copied to dispatched command" do
      correlation_id = UUID.uuid4()

      :ok = AuditedBankRouter.dispatch(%OpenAccount{account_number: "ACC123", initial_balance: 500}, correlation_id: correlation_id)

      assert [^correlation_id] = CommandAuditMiddleware.dispatched_commands(&(&1.correlation_id))
    end

    test "should be set on all created events" do
      correlation_id = UUID.uuid4()

      :ok = AuditedBankRouter.dispatch(%OpenAccount{account_number: "ACC123", initial_balance: 500}, correlation_id: correlation_id)
      :ok = AuditedBankRouter.dispatch(%WithdrawMoney{account_number: "ACC123", amount: 1_000}, correlation_id: correlation_id)

      events = EventStore.stream_forward("ACC123") |> Enum.to_list()
      assert length(events) == 3

      for event <- events do
        assert event.correlation_id == correlation_id
      end
    end
  end
end
