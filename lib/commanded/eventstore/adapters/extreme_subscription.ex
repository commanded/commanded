if Code.ensure_loaded?(Extreme) do 
defmodule Commanded.EventStore.Adapters.ExtremeSubscription do

  use GenServer
  require Logger

  @server Commanded.ExtremeEventStore

  alias Commanded.EventStore.Adapters.ExtremeEventStore

  def start(stream, subscription_name, subscriber, start_from) do
    state = %{
      stream: stream,
      name: subscription_name,
      subscriber: subscriber,
      start_from: start_from,
      result: nil,
      subscription: nil
    }

    GenServer.start(__MODULE__, state)
  end

  def init(state) do
    Process.monitor(state.subscriber)

    Logger.debug(fn -> "subscribe to stream: #{state.stream} | start_from: #{state.start_from}" end)

    from_event_number =
      case state.start_from do
	:origin      -> 0
	:current     -> nil
	event_number -> event_number
      end

    result =
      case from_event_number do
	nil          -> Extreme.subscribe_to(@server, self, state.stream)
	event_number -> Extreme.read_and_stay_subscribed(@server, self, state.stream, event_number)
      end

    state =
      case result do
	{:ok, _} -> %{state | result: {:ok, self}, subscription: self}
	err      -> %{state | result: err}
      end

    {:ok, state}
  end

  def result(pid) do
    GenServer.call(pid, :result)
  end

  def handle_call(:result, _from, state) do
    {:reply, state.result, state}
  end

  def handle_info({:ack, _last_seen_event_id}, state) do
    # not implemented

    {:noreply, state}
  end

  def handle_info({:on_event, event}, state) do
    recorded_ev = ExtremeEventStore.to_recorded_event(event)
    Logger.debug(fn -> "on_event (to: #{inspect state.subscriber}): #{state.name} #{event.event.event_stream_id} | #{inspect recorded_ev.data}" end)

    send(
      state.subscriber,
      {:events, [recorded_ev], state.subscription}
    )

    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    Process.exit(self, :subscriber_shutdown)

    {:noreply, state}
  end

end
end
