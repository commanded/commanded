defmodule Commanded.Commands.Dispatcher do
  @moduledoc false

  require Logger

  alias Commanded.Aggregates.Aggregate
  alias Commanded.Aggregates.ExecutionContext
  alias Commanded.Middleware.Pipeline
  alias Commanded.Telemetry

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
      :handler_before_execute,
      :aggregate_module,
      :identity,
      :identity_prefix,
      :timeout,
      :lifespan,
      :metadata,
      :retry_attempts,
      :returning,
      middleware: []
    ]
  end

  # Dispatch the given command to the handler module for the aggregate as
  # identified.
  @spec dispatch(payload :: struct) ::
          :ok
          | {:ok, aggregate_state :: struct}
          | {:ok, aggregate_version :: non_neg_integer()}
          | {:ok, events :: list(struct)}
          | {:ok, Commanded.Commands.ExecutionResult.t()}
          | {:error, error :: term}
  def dispatch(%Payload{} = payload) do
    pipeline = to_pipeline(payload)
    telemetry_metadata = telemetry_metadata(pipeline, payload)

    start_time = telemetry_start(telemetry_metadata)

    pipeline = before_dispatch(pipeline, payload)

    # Stop command execution if pipeline has been halted
    unless Pipeline.halted?(pipeline) do
      context = to_execution_context(pipeline, payload)

      pipeline
      |> execute(payload, context)
      |> telemetry_stop(start_time, telemetry_metadata)
      |> Pipeline.response()
    else
      pipeline
      |> after_failure(payload)
      |> telemetry_stop(start_time, telemetry_metadata)
      |> Pipeline.response()
    end
  end

  defp to_pipeline(%Payload{} = payload) do
    struct(Pipeline, Map.from_struct(payload))
  end

  defp execute(%Pipeline{} = pipeline, %Payload{} = payload, %ExecutionContext{} = context) do
    %Pipeline{application: application, assigns: %{aggregate_uuid: aggregate_uuid}} = pipeline
    %Payload{aggregate_module: aggregate_module, timeout: timeout} = payload

    {:ok, ^aggregate_uuid} =
      Commanded.Aggregates.Supervisor.open_aggregate(
        application,
        aggregate_module,
        aggregate_uuid
      )

    task_dispatcher_name = Module.concat([application, Commanded.Commands.TaskDispatcher])

    task =
      Task.Supervisor.async_nolink(task_dispatcher_name, Aggregate, :execute, [
        application,
        aggregate_module,
        aggregate_uuid,
        context,
        timeout
      ])

    result =
      case Task.yield(task, timeout) || Task.shutdown(task) do
        {:ok, result} ->
          result

        {:exit, {:normal, :aggregate_stopped}} = result ->
          result

        {:exit, {{:nodedown, _node_name}, {GenServer, :call, _}}} ->
          {:error, :remote_node_down}

        {:exit, _reason} ->
          {:error, :aggregate_execution_failed}

        nil ->
          {:error, :aggregate_execution_timeout}
      end

    case result do
      {:ok, aggregate_version, events} ->
        pipeline
        |> Pipeline.assign(:aggregate_version, aggregate_version)
        |> Pipeline.assign(:events, events)
        |> after_dispatch(payload)
        |> Pipeline.respond(:ok)

      {:ok, aggregate_version, events, reply} ->
        pipeline
        |> Pipeline.assign(:aggregate_version, aggregate_version)
        |> Pipeline.assign(:events, events)
        |> after_dispatch(payload)
        |> Pipeline.respond({:ok, reply})

      {:exit, {:normal, :aggregate_stopped}} ->
        # Maybe retry command when aggregate process stopped by lifespan timeout
        maybe_retry(pipeline, payload, context)

      {:error, :remote_node_down} ->
        # Maybe retry command when aggregate process not found on a remote node
        maybe_retry(pipeline, payload, context)

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
      handler_before_execute: handler_before_execute,
      lifespan: lifespan,
      retry_attempts: retry_attempts,
      returning: returning
    } = payload

    %ExecutionContext{
      command: command,
      causation_id: command_uuid,
      correlation_id: correlation_id,
      metadata: metadata,
      handler: handler_module,
      function: handler_function,
      before_execute: handler_before_execute,
      lifespan: lifespan,
      retry_attempts: retry_attempts,
      returning: returning
    }
  end

  defp before_dispatch(%Pipeline{} = pipeline, %Payload{middleware: middleware}) do
    Pipeline.chain(pipeline, :before_dispatch, middleware)
  end

  defp after_dispatch(%Pipeline{} = pipeline, %Payload{middleware: middleware}) do
    Pipeline.chain(pipeline, :after_dispatch, middleware)
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

  defp after_failure(%Pipeline{} = pipeline, %Payload{} = payload) do
    %Payload{middleware: middleware} = payload

    Pipeline.chain(pipeline, :after_failure, middleware)
  end

  defp telemetry_start(telemetry_metadata) do
    Telemetry.start([:commanded, :application, :dispatch], telemetry_metadata)
  end

  defp telemetry_stop(%Pipeline{assigns: assigns} = pipeline, start_time, telemetry_metadata) do
    event_prefix = [:commanded, :application, :dispatch]

    case assigns do
      %{error: error} ->
        Telemetry.stop(event_prefix, start_time, Map.put(telemetry_metadata, :error, error))

      _ ->
        Telemetry.stop(event_prefix, start_time, telemetry_metadata)
    end

    pipeline
  end

  defp telemetry_metadata(%Pipeline{} = pipeline, %Payload{} = payload) do
    %Payload{application: application} = payload

    context = to_execution_context(pipeline, payload)

    %{
      application: application,
      error: nil,
      execution_context: context
    }
  end

  defp maybe_retry(pipeline, payload, context) do
    case ExecutionContext.retry(context) do
      {:ok, context} ->
        execute(pipeline, payload, context)

      reply ->
        reply
    end
  end
end
