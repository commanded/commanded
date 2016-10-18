defmodule Commanded.Commands.Dispatcher do
  require Logger

  alias Commanded.Aggregates

  @doc """
  Dispatch the given command to the handler module for the aggregate root as identified
  Returns `:ok` on success.
  """
  @spec dispatch(command :: struct, handler_module :: atom, aggregate_module :: atom, identity :: atom) :: :ok | {:error, reason :: term}
  def dispatch(command, handler_module, aggregate_module, identity) do
    Logger.debug(fn -> "attempting to dispatch command: #{inspect command}, to: #{inspect handler_module}, aggregate: #{inspect aggregate_module}, identity: #{inspect identity}" end)

    case Map.get(command, identity) do
      nil -> {:error, :invalid_aggregate_identity}
      aggregate_uuid -> execute(command, handler_module, aggregate_module, aggregate_uuid)
    end
  end

  defp execute(command, handler_module, aggregate_module, aggregate_uuid) do
    {:ok, aggregate} = Aggregates.Registry.open_aggregate(aggregate_module, aggregate_uuid)

    Aggregates.Aggregate.execute(aggregate, command, handler_module)
  end
end
