defmodule Commanded.Event.EventHandlerStateTest do
  use Commanded.MockEventStoreCase

  alias Commanded.Event.StatefulEventHandler
  alias Commanded.Helpers.EventFactory

  defmodule AnEvent do
    @derive Jason.Encoder
    defstruct [:reply_to, :update_state?]
  end

  describe "event handler state" do
    test "initially set in `init/1` function" do
      handler = start_supervised!(StatefulEventHandler)

      event = %AnEvent{reply_to: reply_to(), update_state?: true}
      send_events_to_handler(handler, [event])

      assert_receive {:event, ^event, metadata}
      assert match?(%{state: 0}, metadata)
    end

    test "initially set as runtime option" do
      handler = start_supervised!({StatefulEventHandler, state: 1})

      event = %AnEvent{reply_to: reply_to(), update_state?: true}
      send_events_to_handler(handler, [event])

      assert_receive {:event, ^event, metadata}
      assert match?(%{state: 1}, metadata)
    end

    test "updated by returning `{:ok, new_state}` from `handle/2` function" do
      handler = start_supervised!(StatefulEventHandler)

      event1 = %AnEvent{reply_to: reply_to(), update_state?: true}
      event2 = %AnEvent{reply_to: reply_to(), update_state?: true}
      send_events_to_handler(handler, [event1, event2])

      assert_receive {:event, ^event1, metadata}
      assert match?(%{state: 0}, metadata)

      assert_receive {:event, ^event2, metadata}
      assert match?(%{state: 1}, metadata)
    end

    test "not updated when returning `:ok` from `handle/2` function" do
      handler = start_supervised!(StatefulEventHandler)

      event1 = %AnEvent{reply_to: reply_to(), update_state?: false}
      event2 = %AnEvent{reply_to: reply_to(), update_state?: false}
      send_events_to_handler(handler, [event1, event2])

      assert_receive {:event, ^event1, metadata}
      assert match?(%{state: 0}, metadata)

      assert_receive {:event, ^event2, metadata}
      assert match?(%{state: 0}, metadata)
    end

    test "state is reset when process restarts" do
      opts = [state: 10]
      handler = start_supervised!({StatefulEventHandler, opts})

      event1 = %AnEvent{reply_to: reply_to(), update_state?: true}
      event2 = %AnEvent{reply_to: reply_to(), update_state?: true}
      send_events_to_handler(handler, [event1, event2])

      assert_receive {:event, ^event1, metadata}
      assert match?(%{state: 10}, metadata)

      assert_receive {:event, ^event1, metadata}
      assert match?(%{state: 11}, metadata)

      %{id: id} = StatefulEventHandler.child_spec(state: 10)

      stop_supervised!(id)

      handler = start_supervised!({StatefulEventHandler, opts})

      event3 = %AnEvent{reply_to: reply_to(), update_state?: true}
      send_events_to_handler(handler, [event3], 3)

      assert_receive {:event, ^event3, metadata}
      assert match?(%{state: 10}, metadata)
    end
  end

  defp reply_to, do: :erlang.pid_to_list(self())

  defp send_events_to_handler(handler, events, initial_event_number \\ 1) do
    recorded_events = EventFactory.map_to_recorded_events(events, initial_event_number)

    send(handler, {:events, recorded_events})
  end
end
