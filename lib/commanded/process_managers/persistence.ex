defmodule Commanded.ProcessManagers.Persistence do
  @moduledoc """
  Persistence layer for Process Managers to save snapshots
  """

  alias Commanded.ProcessManagers.ProcessManagerInstance

  def persist_state(%ProcessManagerInstance{process_manager_module: process_manager_module, 
    process_state: process_state} = state, event_id) do

      :ok = EventStore.record_snapshot(%EventStore.Snapshots.SnapshotData{
        source_uuid: process_state_uuid(state),
        source_version: event_id,
        source_type: Atom.to_string(process_manager_module),
        data: process_state
      })
  end

  def fetch_state(%ProcessManagerInstance{} = state) do
    case EventStore.read_snapshot(process_state_uuid(state)) do
      {:ok, snapshot} ->
        %ProcessManagerInstance{state |
          process_state: snapshot.data,
          last_seen_event_id: snapshot.source_version,
        }

      {:error, :snapshot_not_found} ->
        state
    end
  end


  defp process_state_uuid(%ProcessManagerInstance{process_manager_name: process_manager_name, process_uuid: process_uuid}),
    do: "#{process_manager_name}-#{process_uuid}"

end
