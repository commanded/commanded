if Code.ensure_loaded?(EventStore) do 
defmodule Commanded.EventStore.Adapters.EventStoreSubscription do

  require Logger

  use GenServer

  alias Commanded.EventStore.Adapters.EventStoreEventStore

  def start(subscription_name, subscriber, start_from) do
    state = %{
      name: subscription_name,
      subscriber: subscriber,
      start_from: start_from,
      result: nil,
      remote_subscription_pid: nil,
      subscription: nil
    }

    GenServer.start(__MODULE__, state)
  end

  def init(state) do
    Process.monitor(state.subscriber)

    state = 
      case EventStore.subscribe_to_all_streams(state.name, self(), state.start_from) do
	{:ok, pid} ->
	  %{state | result: {:ok, self()}, remote_subscription_pid: pid, subscription: self()}
	err -> %{state | result: err}
      end

    {:ok, state}
  end

  def result(pid) do
    GenServer.call(pid, :result)
  end

  def handle_call(:result, _from, state) do
    {:reply, state.result, state}
  end

  def handle_info({:ack, last_seen_event_id}, state) do
    send(state.remote_subscription_pid, {:ack, last_seen_event_id})

    {:noreply, state}
  end

  def handle_info({:events, events, _subscription_pid}, state) do
    send(
      state.subscriber,
      {:events, Enum.map(events, &EventStoreEventStore.from_pg_recorded_event(&1)), state.subscription}
    )

    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    Process.exit(self(), :subscriber_shutdown)

    {:noreply, state}
  end

end
end
