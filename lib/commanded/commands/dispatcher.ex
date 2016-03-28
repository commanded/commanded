defmodule Commanded.Commands.Dispatcher do
  require Logger

  alias Commanded.Commands
  alias Commanded.Entities

  @spec dispatch(struct) :: :ok
  def dispatch(%{source_uuid: source_uuid} = command) do
    {:ok, handler} = Commands.Registry.handler(command)
    {:ok, entity} = Entities.Registry.open_entity(handler.aggregate, source_uuid)

    Entities.Entity.execute(entity, command, handler)

    :ok
  end
end
