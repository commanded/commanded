defmodule Commanded.Aggregates.AggregateStateBuilder do
  use TelemetryRegistry
  alias Commanded.Aggregates.Aggregate
  alias Commanded.EventStore
  alias Commanded.EventStore.RecordedEvent
  alias Commanded.EventStore.SnapshotData
  alias Commanded.Snapshotting
  alias Commanded.Telemetry

  telemetry_event(%{
    event: [:commanded, :aggregate, :populate, :start],
    description: "Emitted when an aggregate begins loading from the event store",
    measurements: "%{system_time: integer()}",
    metadata: """
    %{application: Commanded.Application.t(),
      aggregate_uuid: String.t(),
      aggregate_state: struct(),
      aggregate_version: non_neg_integer()}
    """
  })

  telemetry_event(%{
    event: [:commanded, :aggregate, :populate, :stop],
    description: "Emitted when an aggregate completes loading from the event store",
    measurements: "%{duration: non_neg_integer(), count: non_neg_integer()}",
    metadata: """
    %{application: Commanded.Application.t(),
      aggregate_uuid: String.t(),
      aggregate_state: struct(),
      aggregate_version: non_neg_integer()}
    """
  })

  @read_event_batch_size 1_000

  @doc """
  Populate the aggregate's state from a snapshot, if present, and it's events.

  Attempt to fetch a snapshot for the aggregate to use as its initial state.
  If the snapshot exists, fetch any subsequent events to rebuild its state.
  Otherwise start with the aggregate struct and stream all existing events for
  the aggregate from the event store to rebuild its state from those events.
  """
  def populate(%Aggregate{} = state) do
    %Aggregate{aggregate_module: aggregate_module, snapshotting: snapshotting} = state

    aggregate =
      case Snapshotting.read_snapshot(snapshotting) do
        {:ok, %SnapshotData{source_version: source_version, data: data}} ->
          %Aggregate{
            state
            | aggregate_version: source_version,
              aggregate_state: data
          }

        {:error, _error} ->
          # No snapshot present, or exists but for outdated state, so use initial empty state
          %Aggregate{state | aggregate_version: 0, aggregate_state: struct(aggregate_module)}
      end

    rebuild_from_events(aggregate)
  end

  @doc """
  Load events from the event store, in batches, to rebuild the aggregate state
  """
  def rebuild_from_events(%Aggregate{} = state) do
    %Aggregate{
      application: application,
      aggregate_uuid: aggregate_uuid,
      aggregate_version: aggregate_version
    } = state

    case EventStore.stream_forward(
           application,
           aggregate_uuid,
           aggregate_version + 1,
           @read_event_batch_size
         ) do
      {:error, :stream_not_found} ->
        # aggregate does not exist, return initial state
        state

      event_stream ->
        rebuild_from_event_stream(event_stream, state)
    end
  end

  # Rebuild aggregate state from a `Stream` of its events.
  defp rebuild_from_event_stream(event_stream, %Aggregate{} = state) do
    telemetry_prefix = [:commanded, :aggregate, :populate]
    start_time = Telemetry.start(telemetry_prefix, telemetry_metadata(state))

    {state, count} =
      Enum.reduce(event_stream, {state, 0}, fn event, {state, count} ->
        %RecordedEvent{data: data, stream_version: stream_version} = event
        %Aggregate{aggregate_module: aggregate_module, aggregate_state: aggregate_state} = state

        state = %{
          state
          | aggregate_version: stream_version,
            aggregate_state: aggregate_module.apply(aggregate_state, data)
        }

        {state, count + 1}
      end)

    Telemetry.stop(telemetry_prefix, start_time, telemetry_metadata(state), %{count: count})

    state
  end

  defp telemetry_metadata(%Aggregate{} = state) do
    %Aggregate{
      application: application,
      aggregate_uuid: aggregate_uuid,
      aggregate_state: aggregate_state,
      aggregate_version: aggregate_version
    } = state

    %{
      application: application,
      aggregate_uuid: aggregate_uuid,
      aggregate_state: aggregate_state,
      aggregate_version: aggregate_version
    }
  end
end
