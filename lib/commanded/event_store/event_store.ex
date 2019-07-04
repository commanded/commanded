defmodule Commanded.EventStore do
  @moduledoc """
  Defines the behaviour to be implemented by an event store adapter to be used by Commanded.
  """

  alias Commanded.EventStore.{EventData, RecordedEvent, SnapshotData}

  @type application :: module
  @type event_store_adapter :: module
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
  Return a child spec defining all processes required by the event store.
  """
  @callback child_spec() :: [:supervisor.child_spec()]

  @doc """
  Append one or more events to a stream atomically.
  """
  @callback append_to_stream(
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
  @callback subscribe(stream_uuid | :all) :: :ok | {:error, error}

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
  @callback subscribe_to(stream_uuid | :all, subscription_name, subscriber, start_from) ::
              {:ok, subscription}
              | {:error, :subscription_already_exists}
              | {:error, error}

  @doc """
  Acknowledge receipt and successful processing of the given event received from
  a subscription to an event stream.
  """
  @callback ack_event(pid, RecordedEvent.t()) :: :ok

  @doc """
  Unsubscribe an existing subscriber from event notifications.

  This will not delete the subscription.

  ## Example

      :ok = Commanded.EventStore.unsubscribe(subscription)

  """
  @callback unsubscribe(subscription) :: :ok

  @doc """
  Delete an existing subscription.

  ## Example

      :ok = Commanded.EventStore.delete_subscription(:all, "Example")

  """
  @callback delete_subscription(stream_uuid | :all, subscription_name) ::
              :ok | {:error, :subscription_not_found} | {:error, error}

  @doc """
  Read a snapshot, if available, for a given source.
  """
  @callback read_snapshot(source_uuid) :: {:ok, snapshot} | {:error, :snapshot_not_found}

  @doc """
  Record a snapshot of the data and metadata for a given source
  """
  @callback record_snapshot(snapshot) :: :ok | {:error, error}

  @doc """
  Delete a previously recorded snapshot for a given source
  """
  @callback delete_snapshot(source_uuid) :: :ok | {:error, error}

  @doc """
  Append one or more events to a stream atomically.
  """
  @spec append_to_stream(
          stream_uuid,
          expected_version,
          events :: list(EventData.t())
        ) :: :ok | {:error, :wrong_expected_version} | {:error, error}
  def append_to_stream(stream_uuid, expected_version, events)
      when is_binary(stream_uuid) and
             (is_integer(expected_version) or
                expected_version in [:any_version, :no_stream, :stream_exists]) and
             is_list(events) do
    event_store_adapter().append_to_stream(stream_uuid, expected_version, events)
  end

  @doc """
  Streams events from the given stream, in the order in which they were
  originally written.
  """
  @spec stream_forward(
          stream_uuid,
          start_version :: non_neg_integer,
          read_batch_size :: non_neg_integer
        ) :: Enumerable.t() | {:error, :stream_not_found} | {:error, error}
  def stream_forward(stream_uuid, start_version \\ 0, read_batch_size \\ 1_000)

  def stream_forward(stream_uuid, start_version, read_batch_size)
      when is_binary(stream_uuid) and is_integer(start_version) and is_integer(read_batch_size) do
    alias Commanded.Event.Upcast

    case event_store_adapter().stream_forward(stream_uuid, start_version, read_batch_size) do
      {:error, _} = error -> error
      stream -> Upcast.upcast_event_stream(stream)
    end
  end

  @doc """
  Create a transient subscription to a single event stream.
  """
  @spec subscribe(stream_uuid | :all) :: :ok | {:error, error}
  def subscribe(stream_uuid) when stream_uuid == :all or is_binary(stream_uuid) do
    event_store_adapter().subscribe(stream_uuid)
  end

  @doc """
  Create a persistent subscription to an event stream.
  """
  @spec subscribe_to(stream_uuid | :all, subscription_name, subscriber, start_from) ::
          {:ok, subscription}
          | {:error, :subscription_already_exists}
          | {:error, error}
  def subscribe_to(stream_uuid, subscription_name, subscriber, start_from)
      when is_binary(subscription_name) and is_pid(subscriber) do
    event_store_adapter().subscribe_to(stream_uuid, subscription_name, subscriber, start_from)
  end

  @doc """
  Acknowledge receipt and successful processing of the given event received from
  a subscription to an event stream.
  """
  @spec ack_event(pid, RecordedEvent.t()) :: :ok
  def ack_event(pid, %RecordedEvent{} = event) when is_pid(pid) do
    event_store_adapter().ack_event(pid, event)
  end

  @doc """
  Unsubscribe an existing subscriber from all event notifications.
  """
  @spec unsubscribe(subscription) :: :ok
  def unsubscribe(subscription) do
    event_store_adapter().unsubscribe(subscription)
  end

  @doc """
  Delete an existing subscription.
  """
  @spec delete_subscription(stream_uuid | :all, subscription_name) ::
          :ok | {:error, :subscription_not_found} | {:error, error}
  def delete_subscription(stream_uuid, subscription_name) do
    event_store_adapter().delete_subscription(stream_uuid, subscription_name)
  end

  @doc """
  Read a snapshot, if available, for a given source.
  """
  @spec read_snapshot(source_uuid) :: {:ok, snapshot} | {:error, :snapshot_not_found}
  def read_snapshot(source_uuid) when is_binary(source_uuid) do
    event_store_adapter().read_snapshot(source_uuid)
  end

  @doc """
  Record a snapshot of the data and metadata for a given source
  """
  @spec record_snapshot(snapshot) :: :ok | {:error, error}
  def record_snapshot(%SnapshotData{} = snapshot) do
    event_store_adapter().record_snapshot(snapshot)
  end

  @doc """
  Delete a previously recorded snapshot for a given source
  """
  @spec delete_snapshot(source_uuid) :: :ok | {:error, error}
  def delete_snapshot(source_uuid) when is_binary(source_uuid) do
    event_store_adapter().delete_snapshot(source_uuid)
  end

  @doc """
  Get the configured event store adapter
  """
  def event_store_adapter do
    Application.get_env(:commanded, :event_store_adapter) ||
      raise ArgumentError,
            "Commanded expects `:event_store_adapter` to be configured in environment"
  end
end
