defmodule EventStore do
  @moduledoc """
  EventStore process to read and write events to a logical event stream

  ## Example usage

      # start the EventStore process
      {:ok, store} = EventStore.start_link

      # append events to stream
      {:ok, events} = EventStore.append_to_stream(store, stream_uuid, expected_version, events)

      # read all events from the stream, starting at the beginning
      {:ok, recorded_events} = EventStore.read_stream_forward(store, stream_uuid)
  """

  use GenServer

  alias EventStore.Storage
  alias EventStore.Subscriptions

  @all_stream "$all"

  @doc """
  Start the EventStore process (including storage and subscriptions) and connect to PostgreSQL.
  """
  def start_link do
    GenServer.start_link(__MODULE__, [])
  end

  @doc """
  Append one or more events to a stream atomically.

    - `storage` an already started `EventStore` pid.

    - `stream_uuid` is used to uniquely identify a stream.

    - `expected_version` is used for optimistic concurrency.
      Specify 0 for the creation of a new stream. An `{:error, wrong_expected_version}` response will be returned if the stream already exists.
      Any positive number will be used to ensure you can only append to the stream if it is at exactly that version.

    - `events` is a list of `%EventStore.EventData{}` structs
  """
  def append_to_stream(store, stream_uuid, expected_version, events) do
    reply = GenServer.call(store, {:append_to_stream, stream_uuid, expected_version, events})
    GenServer.cast(store, {:notify_events, stream_uuid, events})
    reply
  end

  @doc """
  Reads the requested number of events from the given stream, in the order in which they were originally written.

    - `storage` an already started `EventStore` pid.

    - `stream_uuid` is used to uniquely identify a stream.

    - `start_version` optionally, the version number of the first event to read.
      Defaults to the beginning of the stream if not set.

    - `count` optionally, the maximum number of events to read.
      If not set it will return all events from the stream.
  """
  def read_stream_forward(store, stream_uuid, start_version \\ 0, count \\ nil) do
    GenServer.call(store, {:read_stream_forward, stream_uuid, start_version, count})
  end

  @doc """
  Subscriber will be notified of each event persisted to a single stream, once the subscription is established.

    - `store` an already started `EventStore` pid.

    - `stream_uuid` is the stream to subscribe to.
      Use the `$all` identifier to subscribe to events from all streams.

    - `subscription_name` is used to name the subscription group.

    - `subscriber` is a process that will receive `{:event, event}` callback messages.

    Returns `{:ok, subscription}` when subscription succeeds.
  """
  def subscribe_to_stream(store, stream_uuid, subscription_name, subscriber) do
    GenServer.call(store, {:subscribe_to_stream, stream_uuid, subscription_name, subscriber})
  end

  @doc """
  Subscriber will be notified of each event persisted to any stream, once the subscription is established.

    - `store` an already started `EventStore` pid.

    - `subscription_name` is used to name the subscription group.

    - `subscriber` is a process that will receive `{:event, event}` callback messages.

    Returns `{:ok, subscription}` when subscription succeeds.
  """
  def subscribe_to_all_streams(store, subscription_name, subscriber) do
    GenServer.call(store, {:subscribe_to_stream, @all_stream, subscription_name, subscriber})
  end

  def unsubscribe_from_stream(store, stream_uuid, subscription_name) do
    GenServer.call(store, {:unsubscribe_from_stream, stream_uuid, subscription_name})
  end

  def unsubscribe_from_all_streams(store, subscription_name) do
    GenServer.call(store, {:unsubscribe_from_stream, @all_stream, subscription_name})
  end

  def init([]) do
    {:ok, storage} = EventStore.Storage.start_link
    {:ok, subscriptions} = EventStore.Subscriptions.start_link(storage)

    {:ok, %{storage: storage, subscriptions: subscriptions}}
  end

  def handle_call({:append_to_stream, stream_uuid, expected_version, events}, _from, %{storage: storage} = state) do
    reply = Storage.append_to_stream(storage, stream_uuid, expected_version, events)
    {:reply, reply, state}
  end

  def handle_cast({:notify_events, stream_uuid, events}, %{subscriptions: subscriptions} = state) do
    Subscriptions.notify_events(subscriptions, stream_uuid, 0, events) 
    {:noreply, state}
  end

  def handle_call({:read_stream_forward, stream_uuid, start_version, count}, _from, %{storage: storage} = state) do
    reply = Storage.read_stream_forward(storage, stream_uuid, start_version, count)
    {:reply, reply, state}
  end

  def handle_call({:subscribe_to_stream, stream_uuid, subscription_name, subscriber}, _from, %{subscriptions: subscriptions} = state) do
    reply = Subscriptions.subscribe_to_stream(subscriptions, stream_uuid, subscription_name, subscriber)
    {:reply, reply, state}
  end

  def handle_call({:unsubscribe_from_stream, stream_uuid, subscription_name}, _from, %{subscriptions: subscriptions} = state) do
    reply = Subscriptions.unsubscribe_from_stream(subscriptions, stream_uuid, subscription_name)
    {:reply, reply, state}
  end
end
