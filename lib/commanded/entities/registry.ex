defmodule Commanded.Entities.Registry do
  @moduledoc """
  Provides access to an event sourced entity by id
  """

  use GenServer
  require Logger

  alias Commanded.Entities
  alias Commanded.Entities.Registry

  defstruct entities: %{}, supervisor: nil

  def start_link do
    GenServer.start_link(__MODULE__, %Registry{}, name: __MODULE__)
  end

  def open_entity(entity_module, entity_id) do
    GenServer.call(__MODULE__, {:open_entity, entity_module, entity_id})
  end

  def init(%Registry{} = state) do
    {:ok, supervisor} = Entities.Supervisor.start_link

    state = %Registry{state | supervisor: supervisor}

    {:ok, state}
  end

  def handle_call({:open_entity, entity_module, entity_id}, _from, %Registry{entities: entities, supervisor: supervisor} = state) do
    entity = case Map.get(entities, entity_id) do
      nil -> start_entity(supervisor, entity_module, entity_id)
      entity -> entity
    end

    {:reply, {:ok, entity}, %Registry{state | entities: Map.put(entities, entity_id, entity)}}
  end

  def handle_info({:DOWN, _ref, :process, pid, reason}, %Registry{entities: entities} = state) do
    Logger.warn(fn -> "entity process down due to: #{reason}" end)

    {:noreply, %Registry{state | entities: remove_entity(entities, pid)}}
  end

  defp start_entity(supervisor, entity_module, entity_id) do
    {:ok, entity} = Entities.Supervisor.start_entity(supervisor, entity_module, entity_id)
    Process.monitor(entity)
    entity
  end

  defp remove_entity(entities, pid) do
    Enum.reduce(entities, entities, fn
      ({entity_id, entity_pid}, acc) when entity_pid == pid -> Map.delete(acc, entity_id)
      (_, acc) -> acc
    end)
  end
end
