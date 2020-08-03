defmodule Commanded.Mix.Tasks.ResetEventHandlerTest do
  use ExUnit.Case

  alias Commanded.EventStore
  alias Commanded.ExampleDomain.BankApp
  alias Commanded.ExampleDomain.BankAccount.BankAccountHandler
  alias Commanded.ExampleDomain.BankAccount.Events.BankAccountOpened
  alias Commanded.Helpers.Wait

  setup do
    start_supervised!(BankApp)
    :ok
  end

  describe "mix `commanded.reset` task" do
    test "can reset an event handler" do
      stream_uuid = UUID.uuid4()
      initial_events = [%BankAccountOpened{account_number: "ACC123", initial_balance: 1_000}]

      :ok = EventStore.append_to_stream(BankApp, stream_uuid, 0, to_event_data(initial_events))

      start_supervised!(BankAccountHandler)

      Wait.until(fn ->
        assert BankAccountHandler.current_accounts() == ["ACC123"]
      end)

      :ok = BankAccountHandler.change_prefix("PREF_")

      handler_name = "Commanded.ExampleDomain.BankAccount.BankAccountHandler"
      registry_name = Commanded.Event.Handler.name(BankApp, handler_name)

      pid = Commanded.Registration.whereis_name(BankApp, registry_name)

      assert :undefined != pid

      Mix.Tasks.Commanded.Reset.run([
        "--app",
        "Commanded.ExampleDomain.BankApp",
        "--handler",
        handler_name,
        "--quiet"
      ])

      Wait.until(fn ->
        assert BankAccountHandler.current_accounts() == ["PREF_ACC123"]
      end)
    end
  end

  defp to_event_data(events) do
    Commanded.Event.Mapper.map_to_event_data(events,
      causation_id: UUID.uuid4(),
      correlation_id: UUID.uuid4(),
      metadata: %{}
    )
  end
end
