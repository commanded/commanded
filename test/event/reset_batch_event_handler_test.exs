defmodule Commanded.Event.BatchResetEventHandlerTest do
  use ExUnit.Case

  import Commanded.Assertions.EventAssertions

  alias Commanded.Event.Handler
  alias Commanded.Event.Mapper
  alias Commanded.EventStore
  alias Commanded.ExampleDomain.BankAccount.BankAccountBatchHandler
  alias Commanded.ExampleDomain.BankAccount.Events.BankAccountOpened
  alias Commanded.ExampleDomain.BankApp
  alias Commanded.Helpers.Wait
  alias Commanded.Registration
  alias Commanded.UUID

  describe "reset batch event handler" do
    setup do
      start_supervised!(BankApp)

      # The accounts have to outlive the handler, which is restarted by a reset.
      accounts = [fn -> %{prefix: "", accounts: []} end, [name: BankAccountBatchHandler]]
      start_supervised!(%{id: :accounts, start: {Agent, :start_link, accounts}})

      :ok
    end

    test "should be reset when starting from `:origin`" do
      stream_uuid = UUID.uuid4()
      initial_events = [%BankAccountOpened{account_number: "ACC123", initial_balance: 1_000}]

      :ok = EventStore.append_to_stream(BankApp, stream_uuid, 0, to_event_data(initial_events))

      handler = start_supervised!(BankAccountBatchHandler)

      Wait.until(fn ->
        assert BankAccountBatchHandler.current_accounts() == ["ACC123"]
      end)

      :ok = BankAccountBatchHandler.change_prefix("PREF_")

      send(handler, :reset)

      Wait.until(fn ->
        assert BankAccountBatchHandler.current_accounts() == ["PREF_ACC123"]
      end)
    end

    test "should be reset when starting from `:current`" do
      stream_uuid = UUID.uuid4()

      # Ignored initial events
      initial_events = [%BankAccountOpened{account_number: "ACC123", initial_balance: 1_000}]
      :ok = EventStore.append_to_stream(BankApp, stream_uuid, 0, to_event_data(initial_events))

      handler = start_supervised!({BankAccountBatchHandler, start_from: :current})

      Wait.until(fn ->
        assert BankAccountBatchHandler.current_accounts() == []
      end)

      :ok = BankAccountBatchHandler.change_prefix("PREF_")

      ref = Process.monitor(handler)

      send(handler, :reset)

      # Wait for the restarted handler to subscribe, otherwise there is a risk the
      # append_to_stream below is missed by the new subscription.
      assert_receive {:DOWN, ^ref, :process, ^handler, :reset}

      registry_name = Handler.name(BankApp, inspect(BankAccountBatchHandler))

      Wait.until(fn ->
        assert is_pid(Registration.whereis_name(BankApp, registry_name))
      end)

      _ = BankApp |> Registration.whereis_name(registry_name) |> :sys.get_state()

      new_event = [%BankAccountOpened{account_number: "ACC1234", initial_balance: 1_000}]
      :ok = EventStore.append_to_stream(BankApp, stream_uuid, 1, to_event_data(new_event))

      wait_for_event(BankApp, BankAccountOpened, fn event, recorded_event ->
        event.account_number == "ACC1234" and recorded_event.event_number == 2
      end)

      Wait.until(fn ->
        assert BankAccountBatchHandler.current_accounts() == ["PREF_ACC1234"]
      end)
    end
  end

  defp to_event_data(events) do
    Mapper.map_to_event_data(events,
      causation_id: UUID.uuid4(),
      correlation_id: UUID.uuid4(),
      metadata: %{}
    )
  end
end
