defmodule EventStore do
  @moduledoc """
  EventStore client API to read and write events to a logical event stream

  Each of the following client functions expects to receive an already started & initialised `EventStore.Storage` pid.
  
  ## Example usage

      {:ok, store} = EventStore.Storage.start_link
      EventStore.Storage.initialize_store!(store)
  """

  alias EventStore.Storage
  alias EventStore.Subscriptions

  @all_stream "$all"

  @doc """
  Append one or more events to a stream atomically.
    
    - `storage` an already started `EventStore.Storage` pid.

    - `stream_uuid` is used to uniquely identify a stream. It should be a UUID string of exactly 36 characters.

    - `expected_version` is used for optimistic concurrency.
      Specify 0 for the creation of a new stream. An `{:error, wrong_expected_version}` response will be returned if the stream already exists.
      Any positive number will be used to ensure you can only append to the stream if it is at exactly that version.

    - `events` is a list of `%EventStore.EventData{}` structs
  """
  def append_to_stream(storage, stream_uuid, expected_version, events) do
    Storage.append_to_stream(storage, stream_uuid, expected_version, events)
  end

  @doc """
  Reads the requested number of events from the given stream, in the order in which they were originally written.
  
    - `storage` an already started `EventStore.Storage` pid.

    - `stream_uuid` is used to uniquely identify a stream. 
      It should be a UUID string of exactly 36 characters.

    - `start_version` the version number of the first event to read

    - `count` optionally, the maximum number of events to read. 
      If not set it will return all events from the stream.
  """
  def read_stream_forward(storage, stream_uuid, start_version, count \\ nil) do
    Storage.read_stream_forward(storage, stream_uuid, start_version, count)
  end

  @doc """
  Subscriber will be notified of each persisted event after the subscription is established.
  
    - `subscriptions` an already started `EventStore.Subscriptions.Supervisor` pid.

    - `stream_uuid` is the stream to subscribe to. 
      Use the `$all` identifier to subscribe to events from all streams.

    - `subscription_name` is used to name the subscription group.

    - `subscriber` is a process that will receive `{:event, event}` callback messages.

    Returns `{:ok, subscription}` when subscription succeeds. 
  """
  def subscribe_to_stream(subscriptions, stream_uuid, subscription_name, subscriber) do
    Subscriptions.Supervisor.subscribe_to_stream(subscriptions, stream_uuid, subscription_name, subscriber)
  end

  def subscribe_to_all_streams(subscriptions, subscription_name, subscriber) do
    Subscriptions.Supervisor.subscribe_to_stream(subscriptions, @all_stream, subscription_name, subscriber)
  end
end
