defmodule Commanded.EventStore.Adapter do
  @moduledoc false

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @adapter Keyword.fetch!(opts, :adapter)
      @config Keyword.fetch!(opts, :config)

      @behaviour Commanded.EventStore.Adapter

      alias Commanded.EventStore
      alias Commanded.EventStore.{RecordedEvent, SnapshotData}

      def child_spec do
        @adapter.child_spec(__MODULE__, @config)
      end

      def append_to_stream(stream_uuid, expected_version, events)
          when is_binary(stream_uuid) and
                 (is_integer(expected_version) or
                    expected_version in [:any_version, :no_stream, :stream_exists]) and
                 is_list(events) do
        @adapter.append_to_stream(__MODULE__, stream_uuid, expected_version, events)
      end

      def stream_forward(
            stream_uuid,
            start_version \\ 0,
            read_batch_size \\ 1_000
          )
          when is_binary(stream_uuid) and
                 is_integer(start_version) and
                 is_integer(read_batch_size) do
        alias Commanded.Event.Upcast

        case @adapter.stream_forward(__MODULE__, stream_uuid, start_version, read_batch_size) do
          {:error, _} = error -> error
          stream -> Upcast.upcast_event_stream(stream)
        end
      end

      def subscribe(stream_uuid)
          when stream_uuid == :all or is_binary(stream_uuid) do
        @adapter.subscribe(__MODULE__, stream_uuid)
      end

      def subscribe_to(
            stream_uuid,
            subscription_name,
            subscriber,
            start_from
          )
          when is_binary(subscription_name) and is_pid(subscriber) do
        @adapter.subscribe_to(
          __MODULE__,
          stream_uuid,
          subscription_name,
          subscriber,
          start_from
        )
      end

      def ack_event(pid, %RecordedEvent{} = event) when is_pid(pid) do
        @adapter.ack_event(__MODULE__, pid, event)
      end

      def unsubscribe(subscription) do
        @adapter.unsubscribe(__MODULE__, subscription)
      end

      def delete_subscription(stream_uuid, subscription_name) do
        @adapter.delete_subscription(__MODULE__, stream_uuid, subscription_name)
      end

      def read_snapshot(source_uuid) when is_binary(source_uuid) do
        @adapter.read_snapshot(__MODULE__, source_uuid)
      end

      def record_snapshot(%SnapshotData{} = snapshot) do
        @adapter.record_snapshot(__MODULE__, snapshot)
      end

      def delete_snapshot(source_uuid) when is_binary(source_uuid) do
        @adapter.delete_snapshot(__MODULE__, source_uuid)
      end
    end
  end

  alias Commanded.EventStore.{EventData, RecordedEvent, SnapshotData}
  alias Commanded.EventStore.SnapshotData

  @doc """
  Return a child spec defining all processes required by the event store.
  """
  @callback child_spec() :: [:supervisor.child_spec()]

  @doc """
  Append one or more events to a stream atomically.
  """
  @callback append_to_stream(
              Commanded.EventStore.stream_uuid(),
              Commanded.EventStore.expected_version(),
              events :: list(EventData.t())
            ) ::
              :ok
              | {:error, :wrong_expected_version}
              | {:error, term}

  @doc """
  Streams events from the given stream, in the order in which they were
  originally written.
  """
  @callback stream_forward(
              Commanded.EventStore.stream_uuid(),
              start_version :: non_neg_integer,
              read_batch_size :: non_neg_integer
            ) ::
              Enumerable.t()
              | {:error, :stream_not_found}
              | {:error, term}

  @doc """
  Create a transient subscription to a single event stream.

  The event store will publish any events appended to the given stream to the
  `subscriber` process as an `{:events, events}` message.

  The subscriber does not need to acknowledge receipt of the events.
  """
  @callback subscribe(Commanded.EventStore.stream_uuid() | :all) :: :ok | {:error, term}

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
              Commanded.EventStore.stream_uuid() | :all,
              Commanded.EventStore.subscription_name(),
              Commanded.EventStore.subscriber(),
              Commanded.EventStore.start_from()
            ) ::
              {:ok, Commanded.EventStore.subscription()}
              | {:error, :subscription_already_exists}
              | {:error, term}

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
  @callback unsubscribe(Commanded.EventStore.subscription()) :: :ok

  @doc """
  Delete an existing subscription.

  ## Example

      :ok = Commanded.EventStore.delete_subscription(:all, "Example")

  """
  @callback delete_subscription(
              Commanded.EventStore.stream_uuid() | :all,
              Commanded.EventStore.subscription_name()
            ) ::
              :ok | {:error, :subscription_not_found} | {:error, term}

  @doc """
  Read a snapshot, if available, for a given source.
  """
  @callback read_snapshot(Commanded.EventStore.source_uuid()) ::
              {:ok, SnapshotData.t()} | {:error, :snapshot_not_found}

  @doc """
  Record a snapshot of the data and metadata for a given source
  """
  @callback record_snapshot(SnapshotData.t()) :: :ok | {:error, term}

  @doc """
  Delete a previously recorded snapshot for a given source
  """
  @callback delete_snapshot(Commanded.EventStore.source_uuid()) :: :ok | {:error, term}
end
