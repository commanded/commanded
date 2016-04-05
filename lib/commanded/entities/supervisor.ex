defmodule Commanded.Entities.Supervisor do
  @moduledoc """
  Supervise zero, one or more event sourced entities
  """

  use Supervisor
  require Logger

  def start_link do
    Supervisor.start_link(__MODULE__, nil)
  end

  def start_entity(supervisor, entity_module, entity_id) do
    Logger.debug(fn -> "starting entity process for `#{entity_module}` with id #{entity_id}" end)
    
    Supervisor.start_child(supervisor, [entity_module, entity_id])
  end

  def init(_) do
    children = [
      worker(Commanded.Entities.Entity, [], restart: :temporary),
    ]

    supervise(children, strategy: :simple_one_for_one)
  end
end
