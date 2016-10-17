defmodule EventStore.Subscriber do
  use GenServer

  def start_link(receiver) do
    GenServer.start_link(__MODULE__, receiver, [])
  end

  def received_events(server) do
    GenServer.call(server, :received_events)
  end

  def init(receiver) do
    {:ok, %{receiver: receiver, events: []}}
  end

  def handle_info({:events, events, subscription}, %{receiver: receiver} = state) do
    # send events to receiving process
    send(receiver, {:events, events})

    # confirm receipt of received events
    send(subscription, {:ack, List.last(events).event_id})

    {:noreply, %{state | events: state.events ++ events}}
  end

  def handle_call(:received_events, _from, %{events: events} = state) do
    {:reply, events, state}
  end
end
