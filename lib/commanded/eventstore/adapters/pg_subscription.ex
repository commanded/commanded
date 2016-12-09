defmodule Commanded.EventStore.Adapters.PostgresSubscription do

  require Logger

  use GenServer

  alias Commanded.EventStore.Adapters.PostgresEventStore

  def start_link(subscription_name, subscriber) do
    state = %{
      name: subscription_name,
      subscriber: subscriber,
      result: nil,
      remote_subscription_pid: nil,
      subscription: nil
    }

    GenServer.start_link(__MODULE__, state)
  end

  def init(state) do
    Process.monitor(state.subscriber)

    state = 
      case EventStore.subscribe_to_all_streams(state.name, self) do
	{:ok, pid} ->
	  subscription = %{pid: self}
	
	  %{state | result: {:ok, subscription}, remote_subscription_pid: pid, subscription: subscription}
	err -> %{state | result: err}
      end

    {:ok, state}
  end

  def result(pid) do
    GenServer.call(pid, :result)
  end

  def ack_events(pid, last_seen_event_id) do
    GenServer.cast(pid, {:ack_events, last_seen_event_id})
    :ok
  end

  def handle_call(:result, _from, state) do
    {:reply, state.result, state}
  end

  def handle_cast({:ack_events, last_seen_event_id}, state) do
    send(state.remote_subscription_pid, {:ack, last_seen_event_id})

    {:noreply, state}
  end

  def handle_info({:events, events, _subscription_pid}, state) do
    send(
      state.subscriber,
      {:events, Enum.map(events, &PostgresEventStore.from_pg_recorded_event(&1)), state.subscription}
    )

    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    Process.exit(self, :subscriber_shutdown)

    {:noreply, state}
  end

end
