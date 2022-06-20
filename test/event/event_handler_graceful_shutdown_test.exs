defmodule Commanded.Event.EventHandlerGracefulShutdownTest do
  use Commanded.MockEventStoreCase

  alias Commanded.Event.GracefulShutdownHandler
  alias Commanded.Helpers.EventFactory

  defmodule AnEvent do
    @derive Jason.Encoder
    defstruct [:reply_to]
  end

  defmodule EventHandlersSupervisor do
    use Supervisor

    alias Commanded.Event.GracefulShutdownHandler

    def start_link(arg) do
      Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
    end

    def init(_arg) do
      Supervisor.init([GracefulShutdownHandler], strategy: :one_for_one)
    end
  end

  describe "event handler state" do
    test "stop the event handler while it is handling an event" do
      supervisor = start_supervised!(EventHandlersSupervisor, restart: :transient)
      [{_, handler, _, _}] = Supervisor.which_children(supervisor)

      event = %AnEvent{reply_to: self()}
      send_events_to_handler(handler, [event])

      Task.async(fn ->
        Supervisor.stop(supervisor, :shutdown)
      end)

      assert_receive {:event, ^event, _metadata}
      refute_receive {:continue, ^event, _metadata}

      ref = Process.monitor(handler)

      send(handler, :continue)

      assert_receive {:continue, ^event, _metadata}
      assert_receive {:DOWN, ^ref, :process, ^handler, :shutdown}
    end
  end

  defp send_events_to_handler(handler, events, initial_event_number \\ 1) do
    recorded_events = EventFactory.map_to_recorded_events(events, initial_event_number)

    send(handler, {:events, recorded_events})
  end
end
