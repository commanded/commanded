if Code.ensure_loaded?(Extreme) do 
defmodule Commanded.EventStore.Adapters.ExtremeSubscription do

  use GenServer
  require Logger

  @server Commanded.ExtremeEventStore

  alias Commanded.EventStore.Adapters.ExtremeEventStore

  @max_buffer_size 1_000

  def start(stream, subscription_name, subscriber, start_from, opts \\ []) do
    state = %{
      stream: stream,
      name: subscription_name,
      subscriber: subscriber,
      subscriber_ref: nil,
      start_from: start_from,
      result: nil,
      receiver: nil,
      receiver_ref: nil,
      last_rcvd_event_no: nil,
      events_buffer: [],
      inflight_events: [],
      events_total: 0,
      max_buffer_size: opts[:max_buffer_size] || @max_buffer_size
    }

    GenServer.start(__MODULE__, state)
  end

  def init(state) do
    state = %{state | subscriber_ref: Process.monitor(state.subscriber)}

    Logger.debug(fn -> "subscribe to stream: #{state.stream} | start_from: #{state.start_from}" end)

    {:ok, subscribe(state)}
  end

  def result(pid) do
    GenServer.call(pid, :result)
  end

  # call

  def handle_call(:result, _from, state) do
    {:reply, state.result, state}
  end

  # info

  def handle_info({:ack, last_seen_stream_version}, %{inflight_events: inflight} = state) do
    inflight_updated = Enum.filter(inflight, &(&1.stream_version > last_seen_stream_version))
    events_acked_count = length(inflight) - length(inflight_updated)
    state = %{
      state |
      inflight_events: inflight_updated,
      events_total: state.events_total - events_acked_count,
    }
    
    can_subscribe = state.receiver == nil && state.events_total < (state.max_buffer_size/2)
    state = if can_subscribe, do: subscribe(state), else: state

    {:noreply, state}
  end

  def handle_info({:on_event, event}, state) do
    event_type = event.event.event_type

    state = if "$" != String.first(event_type) do
      state
      |> add_event_to_buffer(event)
      |> process_buffer
    else
      Logger.debug(fn -> "ignoring event of type: #{inspect event_type}" end)
      state
    end

    {:noreply, state}
  end

  def handle_info(:caught_up, state) do
    {:noreply, state}
  end
  
  def handle_info({:DOWN, ref, :process, _pid, reason}, %{subscriber_ref: subscriber_ref, receiver_ref: receiver_ref} = state) do
    case {ref, reason} do
      {^subscriber_ref, _} -> Process.exit(self(), :subscriber_shutdown)
      {^receiver_ref, :unsubscribe} -> :noop
      {^receiver_ref, _} -> Process.exit(self(), :receiver_shutdown)
    end

    {:noreply, state}
  end

  # private

  defp subscribe(state) do
    from_event_number =
      case state.start_from do
	:origin      -> 0
	:current     -> nil
	event_number -> event_number
      end

    receiver = spawn_receiver()
    state = %{state | receiver_ref: Process.monitor(receiver)}

    result =
      case from_event_number do
	nil          -> Extreme.subscribe_to(@server, receiver, state.stream)
	event_number -> Extreme.read_and_stay_subscribed(@server, receiver, state.stream, event_number)
      end
    
    case result do
      {:ok, _} -> %{state | result: {:ok, self()}, receiver: receiver}
      err      -> %{state | result: err}
    end
  end

  defp spawn_receiver do
    subscription = self()

    Process.spawn fn ->
      receive_loop = fn(loop) ->
	receive do
	  {:on_event, event} -> send(subscription, {:on_event, event})
	end
	loop.(loop)
      end

      receive_loop.(receive_loop)
    end, []
  end

  defp unsubscribe(state) do
    if state.receiver do
      Process.exit(state.receiver, :unsubscribe)
      %{state | receiver: nil}
    else
      state
    end
  end

  defp add_event_to_buffer(state, ev) do
    if(state.events_total < state.max_buffer_size) do
      %{
	state |
	events_buffer: [ev | state.events_buffer],
	last_rcvd_event_no: ev.event.event_number,
	events_total: state.events_total + 1,
	start_from: ev.event.event_number + 1,
      }
    else
      unsubscribe(state)
    end
  end

  defp process_buffer(%{events_buffer: events_buffer} = state) do
    case events_buffer do
      []      -> state
      _events -> publish_events(state)
    end
  end

  defp publish_events(%{subscriber: subscriber, events_buffer: events}=state) do
    inflight = events
    |> Enum.reverse
    |> Enum.map(&ExtremeEventStore.to_recorded_event/1)

    send(subscriber, {:events, inflight, self()})
    
    %{
      state |
      events_buffer: [],
      inflight_events: inflight ++ state.inflight_events
    }
  end

end
end
