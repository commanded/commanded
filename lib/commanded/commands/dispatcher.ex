defmodule Commanded.Commands.Dispatcher do
  use GenServer
  require Logger

  alias Commanded.Aggregates
  alias Commanded.Middleware.Pipeline

  defmodule Payload do
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

  Returns `:ok` on success, or `{:error, reason}` on failure.
  """
  @spec dispatch(payload :: struct) :: :ok | {:error, reason :: term}
  def dispatch(%Payload{command: command} = payload) do
    pipeline = before_dispatch(%Pipeline{command: command}, payload)

    # don't continue if pipeline halted
    case Map.get(pipeline, :halted, false) do
      true -> respond(pipeline, {:error, :halted})
      false ->
        case extract_aggregate_uuid(payload) do
          nil ->
            error = :invalid_aggregate_identity
            after_failure(pipeline, error, payload)
            {:error, error}

          aggregate_uuid ->
            result = execute(payload, pipeline, aggregate_uuid)
            respond(pipeline, result)
        end
    end
  end

  defp respond(%Pipeline{response: nil}, result), do: result
  defp respond(%Pipeline{response: response}, _result), do: response

  defp execute(
    %Payload{handler_module: handler_module, timeout: timeout} = payload,
    %Pipeline{command: command} = pipeline,
    aggregate_uuid)
  do
    {:ok, aggregate} = open_aggregate(payload, aggregate_uuid)

    task = Task.Supervisor.async_nolink(Commanded.Commands.TaskDispatcher, Aggregates.Aggregate, :execute, [aggregate, command, handler_module, timeout])

    result = case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, reply} -> reply
      {:error, reason} -> {:error, :aggregate_execution_failed, reason}
      {:exit, reason} -> {:error, :aggregate_execution_failed, reason}
      nil -> {:error, :aggregate_execution_timeout}
    end

    case result do
      :ok = reply ->
        after_dispatch(pipeline, payload)
        reply

      {:error, error} = reply ->
        after_failure(pipeline, error, payload)
        reply

      {:error, error, reason} ->
        after_failure(pipeline, error, reason, payload)
        {:error, error}
     end
  end

  defp open_aggregate(%Payload{aggregate_module: aggregate_module}, aggregate_uuid) do
    Aggregates.Registry.open_aggregate(aggregate_module, aggregate_uuid)
  end

  defp extract_aggregate_uuid(%Payload{command: command, identity: identity}), do: Map.get(command, identity)

  defp before_dispatch(%Pipeline{} = pipeline, %Payload{middleware: middleware}) do
    pipeline
    |> Pipeline.chain(:before_dispatch, middleware)
  end

  defp after_dispatch(%Pipeline{} = pipeline, %Payload{middleware: middleware}) do
    pipeline
    |> Pipeline.chain(:after_dispatch, middleware)
  end

  defp after_failure(%Pipeline{} = pipeline, error, %Payload{middleware: middleware}) do
    pipeline
    |> Pipeline.assign(:error, error)
    |> Pipeline.chain(:after_failure, middleware)
  end

  defp after_failure(%Pipeline{} = pipeline, error, reason, %Payload{middleware: middleware}) do
    pipeline
    |> Pipeline.assign(:error, error)
    |> Pipeline.assign(:error_reason, reason)
    |> Pipeline.chain(:after_failure, middleware)
  end
end
