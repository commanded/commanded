defmodule Commanded.ProcessManagers.Persistence do
  @moduledoc """
  Persistence layer for Process Managers to save snapshots
  """

  alias Commanded.ProcessManagers.ProcessManagerInstance
  alias Commanded.Storage

  def persist_state(%ProcessManagerInstance{process_manager_module: process_manager_module, 
    process_state: process_state} = state, event_id) do

    :ok = Storage.persist_state(process_state_uuid(state), event_id, process_manager_module, process_state)
  end

  def fetch_state(%ProcessManagerInstance{} = state) do
    case Storage.fetch_state(process_state_uuid(state), state) do
      {:ok, data, version} ->
        %ProcessManagerInstance{state |
          process_state: data,
          last_seen_event_id: version,
        }
      {:error, :snapshot_not_found} ->
        state
    end
  end



  defp process_state_uuid(%ProcessManagerInstance{process_manager_name: process_manager_name, process_uuid: process_uuid}),
    do: "#{process_manager_name}-#{process_uuid}"

end
