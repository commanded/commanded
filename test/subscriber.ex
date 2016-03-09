defmodule EventStore.Subscriber do
  use GenServer

  def start_link(sender) do
    GenServer.start_link(__MODULE__, sender, [])
  end

  def received_events(server) do
    GenServer.call(server, :received_events)
  end

  def init(sender) do
    {:ok, %{sender: sender, events: []}}
  end

  def handle_info({:events, _stream_uuid, _stream_version, events} = message, state) do
    send(state.sender, message)
    {:noreply, %{state | events: events ++ state.events}}
  end

  def handle_call(:received_events, _from, state) do
    result = state.events |> Enum.reverse
    {:reply, result, state}
  end
end
