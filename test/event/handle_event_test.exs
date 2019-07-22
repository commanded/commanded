defmodule Commanded.Event.HandleEventTest do
  use Commanded.StorageCase

  import Commanded.Enumerable, only: [pluck: 2]
  import Commanded.Assertions.EventAssertions

  alias Commanded.EventStore
  alias Commanded.Event.{AppendingEventHandler, UninterestingEvent}
  alias Commanded.Helpers.EventFactory
  alias Commanded.Helpers.{ProcessHelper, Wait}
  alias Commanded.ExampleDomain.BankAccount.{BankAccountHandler, AccountBalanceHandler}
  alias Commanded.ExampleDomain.BankAccount.Events.{BankAccountOpened, MoneyDeposited}

  describe "balance handler" do
    setup do
      start_supervised!(BankApp)
      handler = start_supervised!(AccountBalanceHandler)

      Wait.until(fn ->
        assert AccountBalanceHandler.subscribed?()
      end)

      [handler: handler]
    end

    test "should be notified of events", %{handler: handler} do
      events = [
        %BankAccountOpened{account_number: "ACC123", initial_balance: 1_000},
        %MoneyDeposited{amount: 50, balance: 1_050}
      ]

      recorded_events = EventFactory.map_to_recorded_events(events)

      send(handler, {:events, recorded_events})

      Wait.until(fn ->
        assert AccountBalanceHandler.current_balance() == 1_050
      end)
    end

    test "should ignore uninterested events", %{handler: handler} do
      # include uninterested events within those the handler is interested in
      events = [
        %UninterestingEvent{},
        %BankAccountOpened{account_number: "ACC123", initial_balance: 1_000},
        %UninterestingEvent{},
        %MoneyDeposited{amount: 50, balance: 1_050},
        %UninterestingEvent{}
      ]

      recorded_events = EventFactory.map_to_recorded_events(events)

      send(handler, {:events, recorded_events})

      Wait.until(fn ->
        assert AccountBalanceHandler.current_balance() == 1_050
      end)
    end

    test "An event handler can be reset (:origin mode)", %{handler: handler} do
      stream_uuid = UUID.uuid4()
      initial_events = [%BankAccountOpened{account_number: "ACC123", initial_balance: 1_000}]

      :ok = EventStore.append_to_stream(stream_uuid, 0, to_event_data(initial_events))

      Wait.until(fn ->
        assert BankAccountHandler.current_accounts() == ["ACC123"]
      end)

      :ok = BankAccountHandler.change_prefix("PREF_")

      send(handler, :reset)

      Wait.until(fn ->
        assert BankAccountHandler.current_accounts() == ["PREF_ACC123"]
      end)
    end

    test "An event handler can be reset (:current mode)" do
      stream_uuid = UUID.uuid4()

      # Ignored events
      initial_events = [%BankAccountOpened{account_number: "ACC123", initial_balance: 1_000}]
      :ok = EventStore.append_to_stream(stream_uuid, 0, to_event_data(initial_events))

      handler = start_supervised!({BankAccountHandler, start_from: :current})

      Wait.until(fn ->
        assert BankAccountHandler.current_accounts() == []
      end)

      :ok = BankAccountHandler.change_prefix("PREF_")

      send(handler, :reset)

      new_event = [%BankAccountOpened{account_number: "ACC1234", initial_balance: 1_000}]
      :ok = EventStore.append_to_stream(stream_uuid, 1, to_event_data(new_event))

      wait_for_event(BankAccountOpened, fn event, recorded_event ->
        event.account_number == "ACC1234" and recorded_event.event_number == 2
      end)

      Wait.until(fn ->
        assert BankAccountHandler.current_accounts() == ["PREF_ACC1234"]
      end)
    end
  end

  describe "appending handler" do
    setup do
      on_exit(fn ->
        ProcessHelper.shutdown(AppendingEventHandler)
      end)
    end

    test "should ignore events created before the event handler's subscription when starting from `:current`" do
      stream_uuid = UUID.uuid4()
      initial_events = [%BankAccountOpened{account_number: "ACC123", initial_balance: 1_000}]
      new_events = [%MoneyDeposited{amount: 50, balance: 1_050}]

      :ok = EventStore.append_to_stream(stream_uuid, 0, to_event_data(initial_events))

      wait_for_event(BankAccountOpened)

      handler = start_supervised!({AppendingEventHandler, start_from: :current})

      assert GenServer.call(handler, :last_seen_event) == nil

      :ok = EventStore.append_to_stream(stream_uuid, 1, to_event_data(new_events))

      wait_for_event(MoneyDeposited, fn event, recorded_event ->
        event.amount == 50 and recorded_event.event_number == 2
      end)

      Wait.until(fn ->
        assert AppendingEventHandler.received_events() == new_events

        [metadata] = AppendingEventHandler.received_metadata()

        assert Map.get(metadata, :event_number) == 2
        assert Map.get(metadata, :stream_id) == stream_uuid
        assert Map.get(metadata, :stream_version) == 2
        assert %DateTime{} = Map.get(metadata, :created_at)

        assert GenServer.call(handler, :last_seen_event) == 2
      end)
    end

    test "should receive events created before the event handler's subscription when starting from `:origin`" do
      stream_uuid = UUID.uuid4()
      initial_events = [%BankAccountOpened{account_number: "ACC123", initial_balance: 1_000}]
      new_events = [%MoneyDeposited{amount: 50, balance: 1_050}]

      :ok = EventStore.append_to_stream(stream_uuid, 0, to_event_data(initial_events))

      handler = start_supervised!({AppendingEventHandler, start_from: :origin})

      :ok = EventStore.append_to_stream(stream_uuid, 1, to_event_data(new_events))

      wait_for_event(MoneyDeposited)

      Wait.until(fn ->
        assert AppendingEventHandler.received_events() == initial_events ++ new_events

        received_metadata = AppendingEventHandler.received_metadata()

        assert pluck(received_metadata, :event_number) == [1, 2]
        assert pluck(received_metadata, :stream_version) == [1, 2]

        Enum.each(received_metadata, fn metadata ->
          assert Map.get(metadata, :stream_id) == stream_uuid
          assert %DateTime{} = Map.get(metadata, :created_at)
        end)
      end)
    end

    test "should ignore already seen events" do
      handler = start_supervised!(AppendingEventHandler)

      events = [
        %BankAccountOpened{account_number: "ACC123", initial_balance: 1_000},
        %MoneyDeposited{amount: 50, balance: 1_050}
      ]

      recorded_events = EventFactory.map_to_recorded_events(events)

      Wait.until(fn ->
        assert AppendingEventHandler.subscribed?()
      end)

      # send each event twice to simulate duplicate receives
      Enum.each(recorded_events, fn recorded_event ->
        send(handler, {:events, [recorded_event]})
        send(handler, {:events, [recorded_event]})
      end)

      Wait.until(fn ->
        assert AppendingEventHandler.received_events() == events
        assert pluck(AppendingEventHandler.received_metadata(), :stream_version) == [1, 2]
      end)
    end
  end

  describe "event handler name" do
    test "should parse string" do
      assert Commanded.Event.Handler.parse_name(__MODULE__, "foo") == "foo"
    end

    test "should parse atom to string" do
      assert Commanded.Event.Handler.parse_name(__MODULE__, :foo) == ":foo"
    end

    test "should parse tuple to string" do
      assert Commanded.Event.Handler.parse_name(__MODULE__, {:foo, :bar}) == "{:foo, :bar}"
    end

    test "should error when parsing empty string" do
      assert_raise RuntimeError, fn ->
        Commanded.Event.Handler.parse_name(__MODULE__, "")
      end
    end

    test "should error when parsing `nil`" do
      assert_raise RuntimeError, fn ->
        Commanded.Event.Handler.parse_name(__MODULE__, nil)
      end
    end
  end

  test "should ensure an application is provided" do
    assert_raise RuntimeError, "UnnamedEventHandler expects `:name` to be given", fn ->
      Code.eval_string("""
        defmodule NoAppEventHandler do
          use Commanded.Event.Handler, name: __MODULE__,
        end
      """)
    end
  end

  test "should ensure an event handler name is provided" do
    assert_raise RuntimeError, "UnnamedEventHandler expects `:name` to be given", fn ->
      Code.eval_string("""
        defmodule UnnamedEventHandler do
          use Commanded.Event.Handler, application: Commanded.DefaultApp,
        end
      """)
    end
  end

  test "should allow using event handler module as name" do
    Code.eval_string("""
      defmodule EventHandler do
        use Commanded.Event.Handler, application: Commanded.DefaultApp, name: __MODULE__
      end
    """)
  end

  describe "Mix task must be able to reset" do
    test "Can reset an event handler" do
      stream_uuid = UUID.uuid4()
      initial_events = [%BankAccountOpened{account_number: "ACC123", initial_balance: 1_000}]

      :ok = EventStore.append_to_stream(stream_uuid, 0, to_event_data(initial_events))

      start_supervised!(BankAccountHandler)

      Wait.until(fn ->
        assert BankAccountHandler.current_accounts() == ["ACC123"]
      end)

      :ok = BankAccountHandler.change_prefix("PREF_")

      pid =
        Commanded.Registration.whereis_name(
          {Commanded.Event.Handler, "Commanded.ExampleDomain.BankAccount.BankAccountHandler"}
        )

      assert :undefined != pid

      Mix.Tasks.Commanded.Reset.run(["Commanded.ExampleDomain.BankAccount.BankAccountHandler"])

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
