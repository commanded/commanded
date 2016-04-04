defmodule Commanded.Commands.Dispatcher do
  require Logger

  alias Commanded.Commands
  alias Commanded.Entities

  @spec dispatch(struct) :: :ok
  def dispatch(%{entity_id: entity_id} = command) do
    with {:ok, handler} <- Commands.Registry.handler(command),
         {:ok, entity} <- Entities.Registry.open_entity(handler.entity, entity_id),
      do: Entities.Entity.execute(entity, command, handler)
  end
end
