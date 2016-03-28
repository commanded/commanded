defmodule Commanded.Entities.Supervisor do
  @moduledoc """
  Supervise zero, one or more event sourced entities
  """

  use Supervisor

  def start_link do
    Supervisor.start_link(__MODULE__, nil)
  end

  def start_entity(supervisor, entity_module, entity_uuid) do
    Supervisor.start_child(supervisor, [entity_module, entity_uuid])
  end

  def init(_) do
    children = [
      worker(Commanded.Entities.Entity, [], restart: :temporary),
    ]

    supervise(children, strategy: :simple_one_for_one)
  end
end
