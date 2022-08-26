defmodule Commanded.Event.EventHandlerBatchStateTest do
  use Commanded.MockEventStoreCase

  alias Commanded.Event.StatefulBatchedEventHandler
  alias Commanded.Helpers.EventFactory

  defmodule AnEvent do
    @derive Jason.Encoder
    defstruct [:reply_to, :increment]
  end

  describe "batched event handler state" do
    test "initially set in `init/1` function" do
      handler = start_supervised!(StatefulBatchedEventHandler)

      event = %AnEvent{reply_to: reply_to(), increment: true}
      send_events_to_handler(handler, [event])

      assert_receive {:batch, [{^event, metadata}]}
      assert match?(%{state: 0}, metadata)
    end

    test "initially set as runtime option" do
      handler = start_supervised!({StatefulBatchedEventHandler, state: 1})

      event = %AnEvent{reply_to: reply_to(), increment: true}
      send_events_to_handler(handler, [event])

      assert_receive {:batch, [{^event, metadata}]}
      assert match?(%{state: 1}, metadata)
    end

    test "updated by returning `{:ok, new_state}` from `handle_batch/2` function" do
      handler = start_supervised!(StatefulBatchedEventHandler)

      event1 = %AnEvent{reply_to: reply_to(), increment: true}
      event2 = %AnEvent{reply_to: reply_to(), increment: true}
      event3 = %AnEvent{reply_to: reply_to(), increment: true}

      send_events_to_handler(handler, [event1, event2])
      assert_receive {:batch, [{^event1, metadata1}, {^event2, metadata2}]}
      assert match?(%{state: 0}, metadata1)
      assert match?(%{state: 0}, metadata2)

      send_events_to_handler(handler, [event3], 3)
      assert_receive {:batch, [{^event3, metadata3}]}
      assert match?(%{state: 2}, metadata3)
    end

    test "not updated when returning `:ok` from `handle_batch/2` function" do
      handler = start_supervised!(StatefulBatchedEventHandler)

      event1 = %AnEvent{reply_to: reply_to(), increment: false}
      event2 = %AnEvent{reply_to: reply_to(), increment: false}

      send_events_to_handler(handler, [event1])
      assert_receive {:batch, [{^event1, metadata}]}
      assert match?(%{state: 0}, metadata)

      send_events_to_handler(handler, [event2], 2)
      assert_receive {:batch, [{^event2, metadata}]}
      assert match?(%{state: 0}, metadata)
    end

    test "state is reset when process restarts" do
      opts = [state: 10]
      handler = start_supervised!({StatefulBatchedEventHandler, opts})

      event1 = %AnEvent{reply_to: reply_to(), increment: true}
      event2 = %AnEvent{reply_to: reply_to(), increment: true}

      send_events_to_handler(handler, [event1])
      assert_receive {:batch, [{^event1, metadata}]}
      assert match?(%{state: 10}, metadata)

      send_events_to_handler(handler, [event2], 2)
      assert_receive {:batch, [{^event2, metadata}]}
      assert match?(%{state: 11}, metadata)

      %{id: id} = StatefulBatchedEventHandler.child_spec(state: 10)

      stop_supervised!(id)

      handler = start_supervised!({StatefulBatchedEventHandler, opts})

      event3 = %AnEvent{reply_to: reply_to(), increment: true}
      send_events_to_handler(handler, [event3], 3)

      assert_receive {:batch, [{^event3, metadata}]}
      assert match?(%{state: 10}, metadata)
    end
  end

  defp reply_to, do: :erlang.pid_to_list(self())

  defp send_events_to_handler(handler, events, initial_event_number \\ 1) do
    recorded_events = EventFactory.map_to_recorded_events(events, initial_event_number)

    send(handler, {:events, recorded_events})
  end
end
