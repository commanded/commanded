defmodule Commanded.EventStore.Adapter do
  @moduledoc """
  Defines the behaviour to be implemented by an event store adapter to be used by Commanded.
  """

  alias Commanded.EventStore.{EventData, RecordedEvent, SnapshotData}

  @type adapter_meta :: map
  @type application :: Commanded.Application.t()
  @type config :: Keyword.t()
  @type stream_uuid :: String.t()
  @type start_from :: :origin | :current | integer
  @type expected_version :: :any_version | :no_stream | :stream_exists | non_neg_integer
  @type subscription_name :: String.t()
  @type subscription :: any
  @type subscriber :: pid
  @type source_uuid :: String.t()
  @type error :: term
  @type options :: Keyword.t()

  @doc """
  Return a child spec defining all processes required by the event store.
  """
  @callback child_spec(application, config) ::
              {:ok, [:supervisor.child_spec() | {module, term} | module], adapter_meta}

  @doc """
  Append one or more events to a stream atomically.
  """
  @callback append_to_stream(
              adapter_meta,
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
              adapter_meta,
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
  @callback subscribe(adapter_meta, stream_uuid | :all) ::
              :ok | {:error, error}

  @doc """
  Create a persistent subscription to an event stream.
  """
  @callback subscribe_to(
              adapter_meta,
              stream_uuid | :all,
              subscription_name,
              subscriber,
              start_from,
              options
            ) ::
              {:ok, subscription}
              | {:error, :subscription_already_exists}
              | {:error, error}

  @doc """
  Acknowledge receipt and successful processing of the given event received from
  a subscription to an event stream.
  """
  @callback ack_event(adapter_meta, pid, RecordedEvent.t()) :: :ok

  @doc """
  Unsubscribe an existing subscriber from event notifications.

  This should not delete the subscription.
  """
  @callback unsubscribe(adapter_meta, subscription) :: :ok

  @doc """
  Delete an existing subscription.
  """
  @callback delete_subscription(
              adapter_meta,
              stream_uuid | :all,
              subscription_name
            ) ::
              :ok | {:error, :subscription_not_found} | {:error, error}

  @doc """
  Read a snapshot, if available, for a given source.
  """
  @callback read_snapshot(adapter_meta, source_uuid) ::
              {:ok, SnapshotData.t()} | {:error, :snapshot_not_found}

  @doc """
  Record a snapshot of the data and metadata for a given source
  """
  @callback record_snapshot(adapter_meta, SnapshotData.t()) ::
              :ok | {:error, error}

  @doc """
  Delete a previously recorded snapshot for a given source
  """
  @callback delete_snapshot(adapter_meta, source_uuid) ::
              :ok | {:error, error}
end
