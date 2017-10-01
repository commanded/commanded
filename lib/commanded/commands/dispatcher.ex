defmodule Commanded.Commands.Dispatcher do
  @moduledoc false
  use GenServer
  require Logger

  alias Commanded.Aggregates
  alias Commanded.Aggregates.ExecutionContext
  alias Commanded.Middleware.Pipeline

  defmodule Payload do
    @moduledoc false
    defstruct [
      command: nil,
      consistency: nil,
      handler_module: nil,
      handler_function: nil,
      aggregate_module: nil,
      include_aggregate_version: nil,
      identity: nil,
      timeout: nil,
      lifespan: nil,
      metadata: nil,
      middleware: [],
    ]
  end

  @doc """
  Dispatch the given command to the handler module for the aggregate root as identified

  Returns `:ok` on success, or `{:error, reason}` on failure.
  """
  @spec dispatch(payload :: struct) :: :ok | {:error, reason :: term}
  def dispatch(%Payload{} = payload) do
    pipeline =
      payload
      |> to_pipeline()
      |> before_dispatch(payload)

    # don't allow command execution if pipeline has been halted
    case Pipeline.halted?(pipeline) do
      true ->
        pipeline
        |> Pipeline.respond({:error, :halted})
        |> after_failure(:halted, payload)
        |> Pipeline.response()

      false ->
        pipeline
        |> execute(payload)
        |> Pipeline.response()
    end
  end

  defp to_pipeline(%Payload{command: command, consistency: consistency, identity: identity}) do
    %Pipeline{command: command, consistency: consistency, identity: identity}
  end

  defp execute(
    %Pipeline{assigns: %{aggregate_uuid: aggregate_uuid}} = pipeline,
    %Payload{timeout: timeout} = payload)
  do
    {:ok, ^aggregate_uuid} = Commanded.Aggregates.Supervisor.open_aggregate(payload.aggregate_module, aggregate_uuid)

    context = to_execution_context(pipeline, payload)
    task = Task.Supervisor.async_nolink(Commanded.Commands.TaskDispatcher, Aggregates.Aggregate, :execute, [aggregate_uuid, context, timeout])
    task_result = Task.yield(task, timeout) || Task.shutdown(task)

    result =
      case task_result do
        {:ok, reply} -> reply
        {:error, reason} -> {:error, :aggregate_execution_failed, reason}
        {:exit, reason} -> {:error, :aggregate_execution_failed, reason}
        nil -> {:error, :aggregate_execution_timeout}
      end

    case result do
      {:ok, aggregate_version} ->
        pipeline
        |> Pipeline.assign(:aggregate_version, aggregate_version)
        |> after_dispatch(payload)
        |> respond_with_success(payload, aggregate_version)

      {:error, error} ->
        pipeline
        |> after_failure(error, payload)
        |> Pipeline.respond({:error, error})

      {:error, error, reason} ->
        pipeline
        |> after_failure(error, reason, payload)
        |> Pipeline.respond({:error, error})
     end
  end

  defp to_execution_context(
    %Pipeline{command: command},
    %Payload{handler_module: handler_module, handler_function: handler_function, lifespan: lifespan, metadata: metadata})
  do
    %ExecutionContext{
      command: command,
      metadata: metadata,
      handler: handler_module,
      function: handler_function,
      lifespan: lifespan,
    }
  end

  defp respond_with_success(%Pipeline{} = pipeline, %Payload{include_aggregate_version: include_aggregate_version}, aggregate_version) do
    response =
      case include_aggregate_version do
        true -> {:ok, aggregate_version}
        false -> :ok
      end

    Pipeline.respond(pipeline, response)
  end

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
