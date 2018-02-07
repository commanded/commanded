defmodule Commanded.Aggregates.AggregateSubscriptionTest do
  use Commanded.StorageCase

  alias Commanded.Aggregates.{Aggregate, ExecutionContext}
  alias Commanded.Aggregates.Supervisor, as: AggregateSupervisor
  alias Commanded.EventStore
  alias Commanded.ExampleDomain.{BankAccount, OpenAccountHandler}
  alias Commanded.ExampleDomain.BankAccount.Commands.OpenAccount
  alias Commanded.ExampleDomain.BankAccount.Events.MoneyDeposited

  describe "append event directly to aggregate stream" do
    setup [
      :open_account,
      :append_event_to_stream
    ]

    test "should notify aggregate and mutate its state", context do
      %{account_number: account_number} = context

      assert Aggregate.aggregate_version(BankAccount, account_number) == 2

      assert Aggregate.aggregate_state(BankAccount, account_number) == %BankAccount{
               account_number: account_number,
               balance: 1_500,
               state: :active
             }
    end

    defp open_account(_context) do
      account_number = UUID.uuid4()

      {:ok, ^account_number} = AggregateSupervisor.open_aggregate(BankAccount, account_number)

      context = %ExecutionContext{
        command: %OpenAccount{account_number: account_number, initial_balance: 1_000},
        handler: OpenAccountHandler,
        function: :handle,
        retry_attempts: 1
      }

      {:ok, 1, _events} = Aggregate.execute(BankAccount, account_number, context)

      [
        account_number: account_number
      ]
    end

    # Write an event to the aggregate's stream, bypassing the aggregate process
    defp append_event_to_stream(%{account_number: account_number}) do
      event = %Commanded.EventStore.EventData{
        event_type: "Elixir.Commanded.ExampleDomain.BankAccount.Events.MoneyDeposited",
        data: %MoneyDeposited{
          account_number: account_number,
          transfer_uuid: UUID.uuid4(),
          amount: 500,
          balance: 1_500
        }
      }

      {:ok, _} = EventStore.append_to_stream(account_number, 1, [event])

      :ok
    end
  end
end
