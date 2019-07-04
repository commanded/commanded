defmodule Commanded.EventStore do
  @moduledoc """
  Defines the behaviour to be implemented by an event store adapter to be used by Commanded.
  """

  alias Commanded.EventStore.{EventData, RecordedEvent, SnapshotData}

  @type application :: module
  @type event_store :: GenServer.server() | module
  @type config :: Keyword.t()
  @type stream_uuid :: String.t()
  @type start_from :: :origin | :current | integer
  @type expected_version :: :any_version | :no_stream | :stream_exists | non_neg_integer
  @type subscription_name :: String.t()
  @type subscription :: any
  @type subscriber :: pid
  @type source_uuid :: String.t()
  @type snapshot :: SnapshotData.t()
  @type error :: term

  @doc """
  Return a child spec defining all processes required by the event store and
  an event store term used for subsequent requests.
  """
  @callback child_spec(application, config) :: [:supervisor.child_spec()]

  @doc """
  Return an identifier for the event store to allow subsequent requests.

  This might be a PID, a value representing a registered name, or a module.
  """
  @callback event_store(application, config) :: event_store

  @doc """
  Append one or more events to a stream atomically.
  """
  @callback append_to_stream(
              event_store,
              stream_uuid,
              expected_version,
              events :: list(EventData.t())
            ) ::
              :ok
              | {:error, :wrong_expected_version}
              | {:error, error}

  @doc """
  Streams events from the given stream, in the order in which they were
  originally written.
  """
  @callback stream_forward(
              event_store,
              stream_uuid,
              start_version :: non_neg_integer,
              read_batch_size :: non_neg_integer
            ) ::
              Enumerable.t()
              | {:error, :stream_not_found}
              | {:error, error}

  @doc """
  Create a transient subscription to a single event stream.

  The event store will publish any events appended to the given stream to the
  `subscriber` process as an `{:events, events}` message.

  The subscriber does not need to acknowledge receipt of the events.
  """
  @callback subscribe(event_store, stream_uuid | :all) :: :ok | {:error, error}

  @doc """
  Create a persistent subscription to an event stream.

  To subscribe to all events appended to any stream use `:all` as the stream
  when subscribing.

  The event store will remember the subscribers last acknowledged event.
  Restarting the named subscription will resume from the next event following
  the last seen.

  Once subscribed, the subscriber process should be sent a
  `{:subscribed, subscription}` message to allow it to defer initialisation
  until the subscription has started.

  The subscriber process will be sent all events persisted to any stream. It
  will receive a `{:events, events}` message for each batch of events persisted
  for a single aggregate.

  The subscriber must ack each received, and successfully processed event, using
  `Commanded.EventStore.ack_event/2`.

  ## Examples

  Subscribe to all streams:

      {:ok, subscription} =
        Commanded.EventStore.subscribe_to(:all, "Example", self(), :current)

  Subscribe to a single stream:

      {:ok, subscription} =
        Commanded.EventStore.subscribe_to("stream1", "Example", self(), :origin)

  """
  @callback subscribe_to(
              event_store,
              stream_uuid | :all,
              subscription_name,
              subscriber,
              start_from
            ) ::
              {:ok, subscription}
              | {:error, :subscription_already_exists}
              | {:error, error}

  @doc """
  Acknowledge receipt and successful processing of the given event received from
  a subscription to an event stream.
  """
  @callback ack_event(event_store, pid, RecordedEvent.t()) :: :ok

  @doc """
  Unsubscribe an existing subscriber from event notifications.

  This will not delete the subscription.

  ## Example

      :ok = Commanded.EventStore.unsubscribe(subscription)

  """
  @callback unsubscribe(event_store, subscription) :: :ok

  @doc """
  Delete an existing subscription.

  ## Example

      :ok = Commanded.EventStore.delete_subscription(:all, "Example")

  """
  @callback delete_subscription(event_store, stream_uuid | :all, subscription_name) ::
              :ok | {:error, :subscription_not_found} | {:error, error}

  @doc """
  Read a snapshot, if available, for a given source.
  """
  @callback read_snapshot(event_store, source_uuid) ::
              {:ok, snapshot} | {:error, :snapshot_not_found}

  @doc """
  Record a snapshot of the data and metadata for a given source
  """
  @callback record_snapshot(event_store, snapshot) :: :ok | {:error, error}

  @doc """
  Delete a previously recorded snapshot for a given source
  """
  @callback delete_snapshot(event_store, source_uuid) :: :ok | {:error, error}
end
