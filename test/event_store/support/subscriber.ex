defmodule Commanded.EventStore.Subscriber do
  use GenServer

  alias Commanded.EventStore.Subscriber

  defmodule State do
    defstruct [:event_store, :owner, :subscription, received_events: [], subscribed?: false]
  end

  alias Subscriber.State

  def start_link(event_store, owner) do
    state = %State{event_store: event_store, owner: owner}

    GenServer.start_link(__MODULE__, state)
  end

  def init(%State{} = state) do
    %State{event_store: event_store} = state

    {:ok, subscription} =
      event_store.subscribe_to(event_store, :all, "subscriber", self(), :origin)

    {:ok, %State{state | subscription: subscription}}
  end

  def subscribed?(subscriber),
    do: GenServer.call(subscriber, :subscribed?)

  def received_events(subscriber),
    do: GenServer.call(subscriber, :received_events)

  def handle_call(:subscribed?, _from, %State{} = state) do
    %State{subscribed?: subscribed?} = state

    {:reply, subscribed?, state}
  end

  def handle_call(:received_events, _from, %State{} = state) do
    %State{received_events: received_events} = state

    {:reply, received_events, state}
  end

  def handle_info({:subscribed, subscription}, %State{subscription: subscription} = state) do
    %State{owner: owner} = state

    send(owner, {:subscribed, subscription})

    {:noreply, %State{state | subscribed?: true}}
  end

  def handle_info({:events, events}, %State{} = state) do
    %State{
      event_store: event_store,
      owner: owner,
      received_events: received_events,
      subscription: subscription
    } = state

    send(owner, {:events, events})

    state = %State{state | received_events: received_events ++ events}

    event_store.ack_event(event_store, subscription, List.last(events))

    {:noreply, state}
  end
end
