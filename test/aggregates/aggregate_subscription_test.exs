defmodule Commanded.Aggregates.AggregateSubscriptionTest do
  use ExUnit.Case

  alias Commanded.Aggregates.{Aggregate, ExecutionContext}
  alias Commanded.Aggregates.Supervisor, as: AggregateSupervisor
  alias Commanded.DefaultApp
  alias Commanded.{EventStore, Registration}
  alias Commanded.ExampleDomain.{BankAccount, OpenAccountHandler}
  alias Commanded.ExampleDomain.BankAccount.Commands.OpenAccount
  alias Commanded.ExampleDomain.BankAccount.Events.MoneyDeposited

  setup do
    start_supervised!(DefaultApp)

    :ok
  end

  describe "append event directly to aggregate stream" do
    setup [
      :open_account,
      :append_event_to_stream
    ]

    test "should notify aggregate and mutate its state", %{account_number: account_number} do
      assert Aggregate.aggregate_version(DefaultApp, BankAccount, account_number) == 2

      assert Aggregate.aggregate_state(DefaultApp, BankAccount, account_number) == %BankAccount{
               account_number: account_number,
               balance: 1_500,
               state: :active
             }
    end

    test "should ignore already seen events", %{account_number: account_number} do
      pid = Registration.whereis_name(DefaultApp, {DefaultApp, BankAccount, account_number})
      events = EventStore.stream_forward(DefaultApp, account_number) |> Enum.to_list()

      # send already seen events multiple times, they should be ignored
      send(pid, {:events, events})
      send(pid, {:events, events})
      send(pid, {:events, events})
      send(pid, {:events, events})

      assert Aggregate.aggregate_version(DefaultApp, BankAccount, account_number) == 2

      assert Aggregate.aggregate_state(DefaultApp, BankAccount, account_number) == %BankAccount{
               account_number: account_number,
               balance: 1_500,
               state: :active
             }
    end

    test "should stop aggregate process when unexpected event received", %{
      account_number: account_number
    } do
      pid = Registration.whereis_name(DefaultApp, {DefaultApp, BankAccount, account_number})
      ref = Process.monitor(pid)

      events =
        EventStore.stream_forward(DefaultApp, account_number)
        |> Enum.to_list()
        |> Enum.map(fn recorded_event ->
          # specify invalid stream version
          %EventStore.RecordedEvent{
            recorded_event
            | stream_version: 999
          }
        end)

      # send invalid events, should stop the aggregate process
      send(pid, {:events, events})

      assert_receive {:DOWN, ^ref, :process, _, :unexpected_event_received}
    end
  end

  defp open_account(_context) do
    account_number = UUID.uuid4()

    {:ok, ^account_number} =
      AggregateSupervisor.open_aggregate(DefaultApp, BankAccount, account_number)

    context = %ExecutionContext{
      command: %OpenAccount{account_number: account_number, initial_balance: 1_000},
      handler: OpenAccountHandler,
      function: :handle,
      retry_attempts: 1
    }

    {:ok, 1, _events} = Aggregate.execute(DefaultApp, BankAccount, account_number, context)

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

    EventStore.append_to_stream(DefaultApp, account_number, 1, [event])
  end
end
