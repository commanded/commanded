defmodule Commanded.Event.HandleEventTest do
  use ExUnit.Case

  import Commanded.Enumerable, only: [pluck: 2]
  import Commanded.Assertions.EventAssertions

  alias Commanded.DefaultApp
  alias Commanded.EventStore
  alias Commanded.Event.AppendingEventHandler
  alias Commanded.Event.UninterestingEvent
  alias Commanded.Helpers.EventFactory
  alias Commanded.Helpers.Wait
  alias Commanded.ExampleDomain.BankApp
  alias Commanded.ExampleDomain.BankAccount.AccountBalanceHandler
  alias Commanded.ExampleDomain.BankAccount.BankAccountHandler
  alias Commanded.ExampleDomain.BankAccount.Events.BankAccountOpened
  alias Commanded.ExampleDomain.BankAccount.Events.MoneyDeposited

  describe "event handling" do
    setup do
      start_supervised!(BankApp)

      handler = start_supervised!(AccountBalanceHandler)

      Wait.until(fn ->
        assert AccountBalanceHandler.subscribed?()
      end)

      [handler: handler]
    end

    test "should handle received events", %{handler: handler} do
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
      # Include uninterested events within those the handler is interested in
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

    test "should ignore unexpected messages", %{handler: handler} do
      import ExUnit.CaptureLog

      ref = Process.monitor(handler)

      send_unexpected_mesage = fn ->
        send(handler, :unexpected_message)

        refute_receive {:DOWN, ^ref, :process, ^handler, _}
      end

      assert capture_log(send_unexpected_mesage) =~
               "Commanded.ExampleDomain.BankAccount.AccountBalanceHandler received unexpected message: :unexpected_message"
    end
  end

  describe "reset event handler" do
    setup do
      start_supervised!(BankApp)

      :ok
    end

    test "should be reset when starting from `:origin`" do
      stream_uuid = UUID.uuid4()
      initial_events = [%BankAccountOpened{account_number: "ACC123", initial_balance: 1_000}]

      :ok = EventStore.append_to_stream(BankApp, stream_uuid, 0, to_event_data(initial_events))

      handler = start_supervised!(BankAccountHandler)

      Wait.until(fn ->
        assert BankAccountHandler.current_accounts() == ["ACC123"]
      end)

      :ok = BankAccountHandler.change_prefix("PREF_")

      send(handler, :reset)

      Wait.until(fn ->
        assert BankAccountHandler.current_accounts() == ["PREF_ACC123"]
      end)
    end

    test "should be reset when starting from `:current`" do
      stream_uuid = UUID.uuid4()

      # Ignored initial events
      initial_events = [%BankAccountOpened{account_number: "ACC123", initial_balance: 1_000}]
      :ok = EventStore.append_to_stream(BankApp, stream_uuid, 0, to_event_data(initial_events))

      handler = start_supervised!({BankAccountHandler, start_from: :current})

      Wait.until(fn ->
        assert BankAccountHandler.current_accounts() == []
      end)

      :ok = BankAccountHandler.change_prefix("PREF_")

      send(handler, :reset)

      new_event = [%BankAccountOpened{account_number: "ACC1234", initial_balance: 1_000}]
      :ok = EventStore.append_to_stream(BankApp, stream_uuid, 1, to_event_data(new_event))

      wait_for_event(BankApp, BankAccountOpened, fn event, recorded_event ->
        event.account_number == "ACC1234" and recorded_event.event_number == 2
      end)

      Wait.until(fn ->
        assert BankAccountHandler.current_accounts() == ["PREF_ACC1234"]
      end)
    end
  end

  describe "appending handler" do
    setup do
      start_supervised!(DefaultApp)

      :ok
    end

    test "should ignore events created before the event handler's subscription when starting from `:current`" do
      stream_uuid = UUID.uuid4()
      initial_events = [%BankAccountOpened{account_number: "ACC123", initial_balance: 1_000}]
      new_events = [%MoneyDeposited{amount: 50, balance: 1_050}]

      :ok = EventStore.append_to_stream(DefaultApp, stream_uuid, 0, to_event_data(initial_events))

      wait_for_event(DefaultApp, BankAccountOpened)

      handler = start_supervised!({AppendingEventHandler, start_from: :current})

      assert GenServer.call(handler, :last_seen_event) == nil

      :ok = EventStore.append_to_stream(DefaultApp, stream_uuid, 1, to_event_data(new_events))

      wait_for_event(DefaultApp, MoneyDeposited, fn event, recorded_event ->
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

      :ok = EventStore.append_to_stream(DefaultApp, stream_uuid, 0, to_event_data(initial_events))

      start_supervised!({AppendingEventHandler, start_from: :origin})

      :ok = EventStore.append_to_stream(DefaultApp, stream_uuid, 1, to_event_data(new_events))

      wait_for_event(DefaultApp, MoneyDeposited)

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
      assert_raise ArgumentError, fn ->
        Commanded.Event.Handler.parse_name(__MODULE__, "")
      end
    end

    test "should error when parsing `nil`" do
      assert_raise ArgumentError, fn ->
        Commanded.Event.Handler.parse_name(__MODULE__, nil)
      end
    end
  end

  test "should ensure an application is provided" do
    assert_raise ArgumentError, "NoAppEventHandler expects :application option", fn ->
      Code.eval_string("""
        defmodule NoAppEventHandler do
          use Commanded.Event.Handler, name: __MODULE__
        end
      """)
    end
  end

  test "should ensure an event handler name is provided" do
    assert_raise ArgumentError, "UnnamedEventHandler expects :name option", fn ->
      Code.eval_string("""
        defmodule UnnamedEventHandler do
          use Commanded.Event.Handler, application: Commanded.DefaultApp
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
    setup do
      start_supervised!(BankApp)

      :ok
    end

    test "Can reset an event handler" do
      stream_uuid = UUID.uuid4()
      initial_events = [%BankAccountOpened{account_number: "ACC123", initial_balance: 1_000}]

      :ok = EventStore.append_to_stream(BankApp, stream_uuid, 0, to_event_data(initial_events))

      start_supervised!(BankAccountHandler)

      Wait.until(fn ->
        assert BankAccountHandler.current_accounts() == ["ACC123"]
      end)

      :ok = BankAccountHandler.change_prefix("PREF_")

      handler_name = BankAccountHandler.__name__()
      registry_name = Commanded.Event.Handler.name(BankApp, handler_name)

      pid = Commanded.Registration.whereis_name(BankApp, registry_name)

      assert :undefined != pid

      Mix.Tasks.Commanded.Reset.run([
        "--app",
        "Commanded.ExampleDomain.BankApp",
        "--handler",
        "Commanded.ExampleDomain.BankAccount.BankAccountHandler",
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
