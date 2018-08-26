defmodule Commanded.EventStore.Subscriber do
  use GenServer

  alias Commanded.EventStore
  alias Commanded.EventStore.Subscriber
  
  defmodule State do
    defstruct received_events: [],
              subscribed?: false,
              subscription: nil
  end

  alias Subscriber.State

  def start_link, do: GenServer.start_link(__MODULE__, %State{})

  def init(%State{} = state) do
    {:ok, subscription} = EventStore.subscribe_to_all_streams("subscriber", self(), :origin)

    {:ok, %State{state | subscription: subscription}}
  end

  def subscribed?(subscriber), do: GenServer.call(subscriber, :subscribed?)

  def received_events(subscriber), do: GenServer.call(subscriber, :received_events)

  def handle_call(:subscribed?, _from, %State{subscribed?: subscribed?} = state) do
    {:reply, subscribed?, state}
  end

  def handle_call(:received_events, _from, %State{received_events: received_events} = state) do
    {:reply, received_events, state}
  end

  def handle_info({:subscribed, subscription}, %State{subscription: subscription} = state) do
    {:noreply, %State{state | subscribed?: true}}
  end

  def handle_info({:events, events}, %State{} = state) do
    %State{received_events: received_events, subscription: subscription} = state

    state = %State{state | received_events: received_events ++ events}

    EventStore.ack_event(subscription, List.last(events))

    {:noreply, state}
  end
end
