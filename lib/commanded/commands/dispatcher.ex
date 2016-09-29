defmodule Commanded.Commands.Dispatcher do
  require Logger

  alias Commanded.Aggregates

  # @spec dispatch(struct) :: :ok
  def dispatch(command, handler_module, aggregate_module, identity) do
    Logger.debug(fn -> "attempting to dispatch command: #{inspect command}, to: #{inspect handler_module}, aggregate: #{inspect aggregate_module}, identity: #{inspect identity}" end)

    aggregate_uuid = Map.get(command, identity)

    {:ok, aggregate} = Aggregates.Registry.open_aggregate(aggregate_module, aggregate_uuid)

    Aggregates.Aggregate.execute(aggregate, command, handler_module)
  end
end
