defmodule Commanded.Middleware.ConsistencyGuarantee do
  @moduledoc """
  An internal `Commanded.Middleware` that blocks after successful command
  dispatch until the requested dispatch consistency has been met.

  Only applies when the requested consistency is `:strong`. Has no effect for
  `:eventual` consistency.
  """

  @behaviour Commanded.Middleware

  require Logger

  alias Commanded.Event.Handler
  alias Commanded.Middleware.Pipeline
  alias Commanded.Subscriptions

  import Pipeline

  def before_dispatch(%Pipeline{} = pipeline) do
    pipeline
    |> Pipeline.assign(:dispatcher_pid, self())
    |> Pipeline.assign(:dispatcher_handler_name, dispatching_handler_name(pipeline))
  end

  def after_dispatch(%Pipeline{consistency: :eventual} = pipeline),
    do: pipeline

  def after_dispatch(%Pipeline{assigns: %{events: []}} = pipeline),
    do: pipeline

  def after_dispatch(%Pipeline{} = pipeline) do
    %Pipeline{
      application: application,
      consistency: consistency,
      assigns: %{
        aggregate_uuid: aggregate_uuid,
        aggregate_version: aggregate_version,
        dispatcher_pid: dispatcher_pid,
        dispatcher_handler_name: dispatcher_handler_name
      }
    } = pipeline

    exclude = [dispatcher_pid | List.wrap(dispatcher_handler_name)]
    opts = [consistency: consistency, exclude: exclude]

    case Subscriptions.wait_for(application, aggregate_uuid, aggregate_version, opts) do
      :ok ->
        pipeline

      {:error, :timeout} ->
        Logger.warning(fn ->
          "Consistency timeout waiting for aggregate #{inspect(aggregate_uuid)} at version #{inspect(aggregate_version)}"
        end)

        respond(pipeline, {:error, :consistency_timeout})
    end
  end

  def after_failure(%Pipeline{} = pipeline), do: pipeline

  # Name of the event handler dispatching the command, but only when dispatching
  # to its own application. The handler is excluded by name as well as by
  # process because a registry adapter may register the handler's subscription
  # with a process other than the handler itself.
  defp dispatching_handler_name(%Pipeline{application: application}) do
    case Handler.handler_identity() do
      {^application, handler_name} -> handler_name
      _other -> nil
    end
  end
end
