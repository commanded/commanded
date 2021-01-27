defmodule Commanded.Event.EventHandlerGracefulShutdownTest do
  use ExUnit.Case

  alias Commanded.Event.GracefulShutdownHandler
  alias Commanded.DefaultApp
  alias Commanded.Helpers.EventFactory

  defmodule AnEvent do
    @derive Jason.Encoder
    defstruct [:reply_to, :sleep_for]
  end

  defmodule EventHandlersSupervisor do
    @moduledoc false

    use Supervisor

    alias Commanded.Event.GracefulShutdownHandler

    def start_link(arg) do
      Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
    end

    def init(_arg) do
      Supervisor.init(
        [
          GracefulShutdownHandler
        ],
        strategy: :one_for_one
      )
    end
  end

  describe "event handler state" do
    setup do
      start_supervised!(DefaultApp)
      :ok
    end

    test "stop the event handler while it is handling an event" do
      supervisor = start_supervised!(EventHandlersSupervisor, restart: :transient)
      {_, handler, _, _} = supervisor |> Supervisor.which_children() |> List.first()

      event = %AnEvent{reply_to: self(), sleep_for: 200}
      send_events_to_handler(handler, [event])
      Supervisor.stop(supervisor, {:shutdown, :graceful})

      assert Process.whereis(EventHandlersSupervisor) == nil
      assert_received {:event, ^event, _metadata}
    end
  end

  defp send_events_to_handler(handler, events, initial_event_number \\ 1) do
    recorded_events = EventFactory.map_to_recorded_events(events, initial_event_number)

    send(handler, {:events, recorded_events})
  end
end
