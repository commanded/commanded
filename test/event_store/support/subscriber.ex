defmodule Commanded.EventStore.Subscriber do
  use GenServer

  alias Commanded.EventStore.Subscriber

  defmodule State do
    defstruct [
      :subscription_opts,
      :event_store,
      :event_store_meta,
      :owner,
      :subscription,
      received_events: [],
      subscribed?: false
    ]
  end

  alias Subscriber.State

  def start_link(event_store, event_store_meta, owner, subscription_opts \\ []) do
    state = %State{
      event_store: event_store,
      event_store_meta: event_store_meta,
      owner: owner,
      subscription_opts: subscription_opts
    }

    GenServer.start_link(__MODULE__, state)
  end

  def init(%State{} = state) do
    %State{event_store: event_store, event_store_meta: event_store_meta, subscription_opts: opts} =
      state

    case event_store.subscribe_to(event_store_meta, :all, "subscriber", self(), :origin, opts) do
      {:ok, subscription} ->
        state = %State{state | subscription: subscription}

        {:ok, state}

      {:error, error} ->
        {:stop, error}
    end
  end

  def ack(subscriber, events),
    do: GenServer.call(subscriber, {:ack, events})

  def subscribed?(subscriber),
    do: GenServer.call(subscriber, :subscribed?)

  def received_events(subscriber),
    do: GenServer.call(subscriber, :received_events)

  def handle_call({:ack, events}, _from, %State{} = state) do
    %State{
      event_store: event_store,
      event_store_meta: event_store_meta,
      subscription: subscription
    } = state

    :ok = event_store.ack_event(event_store_meta, subscription, List.last(events))

    {:reply, :ok, state}
  end

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
    %State{owner: owner, received_events: received_events} = state

    send(owner, {:events, self(), events})

    state = %State{state | received_events: received_events ++ events}

    {:noreply, state}
  end
end
