defmodule Commanded.Commands.Dispatcher do
  @moduledoc false

  require Logger

  alias Commanded.Aggregates.Aggregate
  alias Commanded.Aggregates.ExecutionContext
  alias Commanded.Commands.ExecutionResult
  alias Commanded.Commands.TaskDispatcher
  alias Commanded.Middleware.Pipeline

  defmodule Payload do
    @moduledoc false

    defstruct [
      :application,
      :command,
      :command_uuid,
      :causation_id,
      :correlation_id,
      :consistency,
      :handler_module,
      :handler_function,
      :aggregate_module,
      :include_aggregate_version,
      :include_execution_result,
      :identity,
      :identity_prefix,
      :timeout,
      :lifespan,
      :metadata,
      :retry_attempts,
      middleware: []
    ]
  end

  @doc """
  Dispatch the given command to the handler module for the aggregate as identified

  Returns `:ok` on success, or `{:error, error}` on failure.
  """
  @spec dispatch(payload :: struct) :: :ok | {:error, error :: term}
  def dispatch(%Payload{} = payload) do
    pipeline =
      payload
      |> to_pipeline()
      |> before_dispatch(payload)

    # don't allow command execution if pipeline has been halted
    unless Pipeline.halted?(pipeline) do
      pipeline
      |> execute(payload)
      |> Pipeline.response()
    else
      pipeline
      |> after_failure(payload)
      |> Pipeline.response()
    end
  end

  defp to_pipeline(%Payload{} = payload),
    do: struct(Pipeline, Map.from_struct(payload))

  defp execute(%Pipeline{} = pipeline, %Payload{} = payload) do
    %Pipeline{assigns: %{aggregate_uuid: aggregate_uuid}} = pipeline

    %Payload{application: application, aggregate_module: aggregate_module, timeout: timeout} =
      payload

    {:ok, ^aggregate_uuid} =
      Commanded.Aggregates.Supervisor.open_aggregate(
        application,
        aggregate_module,
        aggregate_uuid
      )

    context = to_execution_context(pipeline, payload)

    task =
      Task.Supervisor.async_nolink(TaskDispatcher, Aggregate, :execute, [
        aggregate_module,
        aggregate_uuid,
        context,
        timeout
      ])

    result =
      case Task.yield(task, timeout) || Task.shutdown(task) do
        {:ok, reply} -> reply
        {:exit, error} -> {:error, :aggregate_execution_failed, error}
        nil -> {:error, :aggregate_execution_timeout}
      end

    case result do
      {:ok, aggregate_version, events} ->
        pipeline
        |> Pipeline.assign(:aggregate_version, aggregate_version)
        |> Pipeline.assign(:events, events)
        |> after_dispatch(payload)
        |> respond_with_success(payload, events)

      {:error, error} ->
        pipeline
        |> Pipeline.respond({:error, error})
        |> after_failure(payload)

      {:error, error, reason} ->
        pipeline
        |> Pipeline.assign(:error_reason, reason)
        |> Pipeline.respond({:error, error})
        |> after_failure(payload)
    end
  end

  defp to_execution_context(%Pipeline{} = pipeline, %Payload{} = payload) do
    %Pipeline{command: command, command_uuid: command_uuid, metadata: metadata} = pipeline

    %Payload{
      correlation_id: correlation_id,
      handler_module: handler_module,
      handler_function: handler_function,
      lifespan: lifespan,
      retry_attempts: retry_attempts
    } = payload

    %ExecutionContext{
      command: command,
      causation_id: command_uuid,
      correlation_id: correlation_id,
      metadata: metadata,
      handler: handler_module,
      function: handler_function,
      lifespan: lifespan,
      retry_attempts: retry_attempts
    }
  end

  defp respond_with_success(%Pipeline{} = pipeline, payload, events) do
    response =
      case payload do
        %{include_execution_result: true} ->
          {
            :ok,
            %ExecutionResult{
              aggregate_uuid: pipeline.assigns.aggregate_uuid,
              aggregate_version: pipeline.assigns.aggregate_version,
              events: events,
              metadata: pipeline.metadata
            }
          }

        %{include_aggregate_version: true} ->
          {:ok, pipeline.assigns.aggregate_version}

        _ ->
          :ok
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

  defp after_failure(%Pipeline{response: {:error, error}} = pipeline, %Payload{} = payload) do
    %Payload{middleware: middleware} = payload

    pipeline
    |> Pipeline.assign(:error, error)
    |> Pipeline.chain(:after_failure, middleware)
  end

  defp after_failure(
         %Pipeline{response: {:error, error, reason}} = pipeline,
         %Payload{} = payload
       ) do
    %Payload{middleware: middleware} = payload

    pipeline
    |> Pipeline.assign(:error, error)
    |> Pipeline.assign(:error_reason, reason)
    |> Pipeline.chain(:after_failure, middleware)
  end

  defp after_failure(%Pipeline{} = pipeline, %Payload{middleware: middleware}) do
    pipeline
    |> Pipeline.chain(:after_failure, middleware)
  end
end
