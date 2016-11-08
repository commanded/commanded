defmodule Commanded.Commands.Dispatcher do
  require Logger

  alias Commanded.Aggregates
  alias Commanded.Middleware.Pipeline

  defmodule Context do
    defstruct [
      command: nil,
      handler_module: nil,
      aggregate_module: nil,
      identity: nil,
      timeout: nil,
      middleware: [],
    ]
  end

  @doc """
  Dispatch the given command to the handler module for the aggregate root as identified
  Returns `:ok` on success.
  """
  @spec dispatch(context :: struct) :: :ok | {:error, reason :: term}
  def dispatch(%Context{command: command, identity: identity} = context) do
    Logger.debug(fn -> "attempting to dispatch command: #{inspect command}, to: #{inspect context.handler_module}, aggregate: #{inspect context.aggregate_module}, identity: #{inspect identity}" end)

    case Map.get(command, identity) do
      nil -> {:error, :invalid_aggregate_identity}
      aggregate_uuid -> execute(context, aggregate_uuid)
    end
  end

  defp execute(%Context{command: command, aggregate_module: aggregate_module, handler_module: handler_module, timeout: timeout, middleware: middleware}, aggregate_uuid) do
    pipeline =
      %Pipeline{
        command: command,
        timeout: timeout,
      }
      |> before_dispatch(middleware)

    {:ok, aggregate} = Aggregates.Registry.open_aggregate(aggregate_module, aggregate_uuid)

    reply = Aggregates.Aggregate.execute(aggregate, command, handler_module, timeout)

    case reply do
      :ok -> after_dispatch(pipeline, middleware)
      {:error, error} -> after_failure(pipeline, error, middleware)
    end

    reply
  end

  def before_dispatch(%Pipeline{} = pipeline, middleware) do
    pipeline
    |> Pipeline.chain(:before_dispatch, middleware)
  end

  def after_dispatch(%Pipeline{} = pipeline, middleware) do
    pipeline
    |> Pipeline.chain(:after_dispatch, middleware)
  end

  def after_failure(%Pipeline{} = pipeline, error, middleware) do
    pipeline
    |> Pipeline.assign(:error, error)
    |> Pipeline.chain(:after_failure, middleware)
  end
end
