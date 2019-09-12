defmodule Commanded.Snapshotting do
  @moduledoc false

  alias Commanded.EventStore
  alias Commanded.EventStore.{SnapshotData, TypeProvider}
  alias Commanded.Snapshotting

  defstruct [
    :application,
    :source_uuid,
    :snapshot_every,
    :snapshot_module_version,
    snapshot_version: 0
  ]

  def new(application, source_uuid, opts) do
    %Snapshotting{
      application: application,
      source_uuid: source_uuid,
      snapshot_every: Keyword.get(opts, :snapshot_every),
      snapshot_module_version: Keyword.get(opts, :snapshot_version, 1)
    }
  end

  def read_snapshot(%Snapshotting{} = snapshotting) do
    %Snapshotting{application: application, source_uuid: source_uuid} = snapshotting

    with :ok <- validate_configured(snapshotting),
         {:ok, snapshot} <- EventStore.read_snapshot(application, source_uuid),
         :ok <- validate_snapshot(snapshotting, snapshot) do
      {:ok, snapshot}
    end
  end

  @doc """
  Take a snapshot of the source state.
  """
  def take_snapshot(%Snapshotting{} = snapshotting, source_version, source_state)
      when is_number(source_version) do
    %Snapshotting{
      application: application,
      source_uuid: source_uuid,
      snapshot_module_version: snapshot_module_version
    } = snapshotting

    snapshot = %SnapshotData{
      source_uuid: source_uuid,
      source_version: source_version,
      source_type: TypeProvider.to_string(source_state),
      data: source_state,
      metadata: %{"snapshot_module_version" => snapshot_module_version}
    }

    case EventStore.record_snapshot(application, snapshot) do
      :ok -> {:ok, %Snapshotting{snapshotting | snapshot_version: source_version}}
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Take a snapshot now?
  """
  def snapshot_required?(%Snapshotting{} = snapshotting, source_version)
      when is_integer(source_version) do
    %Snapshotting{snapshot_every: snapshot_every, snapshot_version: snapshot_version} =
      snapshotting

    enabled?(snapshotting) && source_version - snapshot_version >= snapshot_every
  end

  defp validate_configured(%Snapshotting{} = snapshotting) do
    if enabled?(snapshotting) do
      :ok
    else
      {:error, :snapshotting_not_configured}
    end
  end

  # Is snapshotting configured?
  defp enabled?(%Snapshotting{snapshot_every: snapshot_every}),
    do: is_integer(snapshot_every) && snapshot_every > 0

  # Was the snapshot taken at the expected module version?
  defp validate_snapshot(%Snapshotting{} = snapshotting, %SnapshotData{} = snapshot) do
    %Snapshotting{snapshot_module_version: snapshot_module_version} = snapshotting
    %SnapshotData{metadata: metadata} = snapshot

    if Map.get(metadata, "snapshot_module_version", 1) == snapshot_module_version do
      :ok
    else
      {:error, :outdated_snapshot}
    end
  end
end
