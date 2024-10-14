defmodule Commanded.Event.EventHandlerPersistentStateTest do
  use Commanded.MockEventStoreCase

  alias Commanded.Event.StatefulEventHandler
  alias Commanded.EventStore.SnapshotData
  alias Commanded.Helpers.EventFactory
  alias Commanded.MockedApp

  defmodule AnEvent do
    @derive Jason.Encoder
    defstruct [:reply_to, :update_state?]
  end

  describe "event handler state with permanent persistence" do
    alias Commanded.EventStore.Adapters.Mock, as: MockEventStore

    test "initially set in `init/1` function without previous snapshot" do
      {:ok, subscription} = start_subscription()

      MockEventStore
      |> stub(:subscribe_to, fn _, _, _, _, _, _ -> {:ok, subscription} end)
      |> expect(:record_snapshot, fn _, _ -> :ok end)
      |> expect(:read_snapshot, fn _, _ -> {:error, :snapshot_not_found} end)

      handler =
        start_supervised!({
          StatefulEventHandler,
          persistence: :permanent, application: MockedApp
        })

      event = %AnEvent{reply_to: reply_to(), update_state?: true}
      send_events_to_handler(handler, [event])

      assert_receive {:event, ^event, metadata}
      assert match?(%{state: 0}, metadata)
    end

    test "initially set in `init/1` function wit previous snapshot" do
      {:ok, subscription} = start_subscription()

      MockEventStore
      |> stub(:subscribe_to, fn _event_store, _snapshot, _, _, _, _ -> {:ok, subscription} end)
      |> expect(:record_snapshot, fn _, _ -> :ok end)
      |> expect(:read_snapshot, fn _, _ -> {:ok, %SnapshotData{data: 3}} end)

      handler =
        start_supervised!({
          StatefulEventHandler,
          persistence: :permanent, application: MockedApp
        })

      event = %AnEvent{reply_to: reply_to(), update_state?: true}
      send_events_to_handler(handler, [event])

      assert_receive {:event, ^event, metadata}
      assert match?(%{state: 3}, metadata)
    end

    test "updated by returning `{:ok, new_state}` from `handle/2` function" do
      {:ok, subscription} = start_subscription()

      MockEventStore
      |> stub(:subscribe_to, fn _, _, _, _, _, _ -> {:ok, subscription} end)
      |> expect(:read_snapshot, fn _, _ -> {:error, :snapshot_not_found} end)
      |> expect(:record_snapshot, fn _, %_{data: 1} -> :ok end)
      |> expect(:record_snapshot, fn _, %_{data: 2} -> :ok end)
      |> expect(:ack_event, 2, fn _, _, _ -> :ok end)

      handler =
        start_supervised!({
          StatefulEventHandler,
          persistence: :permanent, application: MockedApp
        })

      event1 = %AnEvent{reply_to: reply_to(), update_state?: true}
      event2 = %AnEvent{reply_to: reply_to(), update_state?: true}
      send_events_to_handler(handler, [event1, event2])

      assert_receive {:event, ^event1, metadata}
      assert match?(%{state: 0}, metadata)

      assert_receive {:event, ^event2, metadata}
      assert match?(%{state: 1}, metadata)
    end

    test "not updated when returning `:ok` from `handle/2` function" do
      {:ok, subscription} = start_subscription()

      MockEventStore
      |> stub(:subscribe_to, fn _, _, _, _, _, _ -> {:ok, subscription} end)
      |> expect(:record_snapshot, fn _, _ -> :ok end)
      |> expect(:read_snapshot, fn _, _ -> {:error, :snapshot_not_found} end)
      |> expect(:ack_event, 2, fn _, _, _ -> :ok end)

      handler =
        start_supervised!({
          StatefulEventHandler,
          persistence: :permanent, application: MockedApp
        })

      event1 = %AnEvent{reply_to: reply_to(), update_state?: false}
      event2 = %AnEvent{reply_to: reply_to(), update_state?: false}
      send_events_to_handler(handler, [event1, event2])

      assert_receive {:event, ^event1, metadata}
      assert match?(%{state: 0}, metadata)

      assert_receive {:event, ^event2, metadata}
      assert match?(%{state: 0}, metadata)
    end

    test "state is NOT reset when process restarts" do
      {:ok, subscription} = start_subscription()

      MockEventStore
      |> stub(:subscribe_to, fn _, _, _, _, _, _ -> {:ok, subscription} end)
      |> expect(:read_snapshot, 1, fn _, _ -> {:ok, %SnapshotData{data: 10}} end)
      |> expect(:record_snapshot, 1, fn _, _ -> :ok end)
      |> expect(:read_snapshot, 1, fn _, _ -> {:ok, %SnapshotData{data: 11}} end)

      handler =
        start_supervised!({
          StatefulEventHandler,
          persistence: :permanent, application: MockedApp, state: 10
        })

      event1 = %AnEvent{reply_to: reply_to(), update_state?: true}
      send_events_to_handler(handler, [event1])

      assert_receive {:event, ^event1, metadata}
      assert match?(%{state: 10}, metadata)

      # Restart app
      stop_supervised!(MockedApp)
      start_supervised!(MockedApp)

      handler =
        start_supervised!({
          StatefulEventHandler,
          persistence: :permanent, application: MockedApp
        })

      event2 = %AnEvent{reply_to: reply_to(), update_state?: false}
      send_events_to_handler(handler, [event2])

      assert_receive {:event, ^event2, metadata}
      assert match?(%{state: 11}, metadata)
    end
  end

  defp reply_to, do: :erlang.pid_to_list(self())

  defp send_events_to_handler(handler, events, initial_event_number \\ 1) do
    recorded_events = EventFactory.map_to_recorded_events(events, initial_event_number)

    send(handler, {:events, recorded_events})
  end

  defp start_subscription do
    pid =
      spawn_link(fn ->
        receive do
          :shutdown -> :ok
        end
      end)

    {:ok, pid}
  end
end
