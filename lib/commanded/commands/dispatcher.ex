defmodule Commanded.Commands.Dispatcher do
  @moduledoc false
  use GenServer
  require Logger

  alias Commanded.Aggregates
  alias Commanded.Middleware.Pipeline

  defmodule Payload do
    @moduledoc false
    defstruct [
      command: nil,
      metadata: nil,
      handler_module: nil,
      handler_function: nil,
      aggregate_module: nil,
      include_aggregate_version: nil,
      identity: nil,
      timeout: nil,
      lifespan: nil,
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

    # don't allow command execution if pipeline has been halted
    case Map.get(pipeline, :halted, false) do
      true ->
        respond_with_failure(pipeline, {:error, :halted}, payload)

      false ->
        case extract_aggregate_uuid(payload) do
          nil ->
            respond_with_failure(pipeline, {:error, :invalid_aggregate_identity}, payload)

          aggregate_uuid ->
            result = execute(payload, pipeline, aggregate_uuid)

            extract_response(pipeline, result)
        end
    end
  end

  defp respond_with_failure(pipeline, error, payload) do
    response = extract_response(pipeline, error)

    after_failure(pipeline, response, payload)

    response
  end

  defp execute(
    %Payload{metadata: metadata, handler_module: handler_module, handler_function: handler_function, include_aggregate_version: include_aggregate_version, timeout: timeout, lifespan: lifespan} = payload,
    %Pipeline{command: command} = pipeline,
    aggregate_uuid)
  do
    {:ok, ^aggregate_uuid} = Commanded.Aggregates.Supervisor.open_aggregate(payload.aggregate_module, aggregate_uuid)

    task = Task.Supervisor.async_nolink(Commanded.Commands.TaskDispatcher, Aggregates.Aggregate, :execute, [aggregate_uuid, command, metadata, handler_module, handler_function, timeout, lifespan])
    task_result = Task.yield(task, timeout) || Task.shutdown(task)

    result = case task_result do
      {:ok, reply} -> reply
      {:error, reason} -> {:error, :aggregate_execution_failed, reason}
      {:exit, reason} -> {:error, :aggregate_execution_failed, reason}
      nil -> {:error, :aggregate_execution_timeout}
    end

    case result do
      {:ok, aggregate_version} ->
        after_dispatch(pipeline, payload)

        case include_aggregate_version do
          true -> {:ok, aggregate_version}
          false -> :ok
        end

      {:error, error} = reply ->
        after_failure(pipeline, error, payload)
        reply

      {:error, error, reason} ->
        after_failure(pipeline, error, reason, payload)
        {:error, error}
     end
  end

  defp extract_aggregate_uuid(%Payload{command: command, identity: identity}), do: Map.get(command, identity)

  defp extract_response(%Pipeline{response: nil}, response), do: response
  defp extract_response(%Pipeline{response: response}, _response), do: response

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
