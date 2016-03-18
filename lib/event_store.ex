defmodule EventStore do
  @moduledoc """
  EventStore client API to read & write events to a logical event stream and subscribe to event notifications

  ## Example usage

      # ensure the event store application has been started
      Application.ensure_all_started(:eventstore)

      # append events to a stream
      {:ok, persisted_events} = EventStore.append_to_stream(stream_uuid, expected_version, events)

      # read all events from a stream, starting at the beginning
      {:ok, recorded_events} = EventStore.read_stream_forward(stream_uuid)
  """

  alias EventStore.{Publisher,Storage,Streams,Subscriptions}
  alias EventStore.Streams.Stream

  @all_stream "$all"

  def append_to_stream(@all_stream, expected_version, events) do
    {:error, :cannot_append_to_all_stream}
  end

  @doc """
  Append one or more events to a stream atomically.

    - `stream_uuid` is used to uniquely identify a stream.

    - `expected_version` is used for optimistic concurrency.
      Specify 0 for the creation of a new stream. An `{:error, wrong_expected_version}` response will be returned if the stream already exists.
      Any positive number will be used to ensure you can only append to the stream if it is at exactly that version.

    - `events` is a list of `%EventStore.EventData{}` structs
      EventStore does not have any built-in serialization.
      The payload and headers for each event should already be serialized to binary data before appending to the stream.
  """
  def append_to_stream(stream_uuid, expected_version, events) do
    {:ok, stream} = Streams.open_stream(stream_uuid)

    case Stream.append_to_stream(stream, expected_version, events) do
      {:ok, persisted_events} = reply ->
        Publisher.notify_events(stream_uuid, persisted_events)
        reply
      reply -> reply
    end
  end

  @doc """
  Reads the requested number of events from the given stream, in the order in which they were originally written.

    - `stream_uuid` is used to uniquely identify a stream.

    - `start_version` optionally, the version number of the first event to read.
      Defaults to the beginning of the stream if not set.

    - `count` optionally, the maximum number of events to read.
      If not set it will return all events from the stream.
  """
  def read_stream_forward(stream_uuid, start_version \\ 0, count \\ nil) do
    Storage.read_stream_forward(stream_uuid, start_version, count)
  end

  @doc """
  Subscriber will be notified of each event persisted to a single stream.

    - `stream_uuid` is the stream to subscribe to.
      Use the `$all` identifier to subscribe to events from all streams.

    - `subscription_name` is used to name the subscription group.

    - `subscriber` is a process that will receive `{:event, event}` callback messages.

  Returns `{:ok, subscription}` when subscription succeeds.
  """
  def subscribe_to_stream(stream_uuid, subscription_name, subscriber) do
    Subscriptions.subscribe_to_stream(stream_uuid, subscription_name, subscriber)
  end

  @doc """
  Subscriber will be notified of each event persisted to any stream.

    - `subscription_name` is used to name the subscription group.

    - `subscriber` is a process that will receive `{:event, event}` callback messages.

  Returns `{:ok, subscription}` when subscription succeeds.
  """
  def subscribe_to_all_streams(subscription_name, subscriber) do
    Subscriptions.subscribe_to_stream(@all_stream, subscription_name, subscriber)
  end

  @doc """
  Unsubscribe an existing subscriber from event notifications.

    - `stream_uuid` is the stream to subscribe to.
      Use the `$all` identifier to subscribe to events from all streams.

    - `subscription_name` is used to name the subscription group.

    - `subscriber` is a process that will receive `{:event, event}` callback messages.

  Returns `:ok` on success.
  """
  def unsubscribe_from_stream(stream_uuid, subscription_name) do
    Subscriptions.unsubscribe_from_stream(stream_uuid, subscription_name)
  end

  def unsubscribe_from_all_streams(subscription_name) do
    Subscriptions.unsubscribe_from_stream(@all_stream, subscription_name)
  end
end
