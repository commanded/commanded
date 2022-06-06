defmodule Commanded.EventStore.Adapters.InMemory.Subscriber do
  @moduledoc false

  alias Commanded.EventStore.RecordedEvent
  alias __MODULE__

  defstruct [:pid, in_flight_events: [], pending_events: []]

  def new(pid), do: %Subscriber{pid: pid}

  def available?(%Subscriber{in_flight_events: []}), do: true
  def available?(%Subscriber{}), do: false

  def ack(%Subscriber{} = subscriber, ack) do
    %Subscriber{in_flight_events: in_flight_events, pending_events: pending_events} = subscriber

    in_flight_events =
      Enum.reject(in_flight_events, fn %RecordedEvent{event_number: event_number} ->
        event_number <= ack
      end)

    subscriber = %Subscriber{subscriber | in_flight_events: in_flight_events}

    case pending_events do
      [pending_event | pending_events] ->
        subscriber = %Subscriber{subscriber | pending_events: pending_events}

        send_event(subscriber, pending_event)

      [] ->
        subscriber
    end
  end

  def publish(%Subscriber{} = subscriber, %RecordedEvent{} = event) do
    %Subscriber{in_flight_events: in_flight_events, pending_events: pending_events} = subscriber

    if Enum.any?(in_flight_events) do
      %Subscriber{subscriber | pending_events: pending_events ++ [event]}
    else
      send_event(subscriber, event)
    end
  end

  defp send_event(%Subscriber{} = subscriber, %RecordedEvent{} = event) do
    %Subscriber{in_flight_events: in_flight_events, pid: pid} = subscriber

    send(pid, {:events, [event]})

    %Subscriber{subscriber | in_flight_events: in_flight_events ++ [event]}
  end
end
