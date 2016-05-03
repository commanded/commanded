defmodule Commanded.Commands.Dispatcher do
  require Logger

  alias Commanded.Commands
  alias Commanded.Aggregates

  @spec dispatch(struct) :: :ok
  def dispatch(command) do
    with {:ok, handler} <- Commands.Registry.handler(command),
         {:ok, aggregate} <- Aggregates.Registry.open_aggregate(command.aggregate, command.aggregate_uuid),
      do: Aggregates.Aggregate.execute(aggregate, command, handler)
  end
end
