defmodule Commanded.Middleware.ConsistencyGuarantee do
  @moduledoc """
  A `Commanded.Middleware` that blocks after successful command dispatch until
  the requested dispatch consistency has been met.

  Only applies when the requested consistency is `:strong`. Has no effect for
  `:eventual` consistency.
  """

  @behaviour Commanded.Middleware

  require Logger

  alias Commanded.Middleware.Pipeline
  alias Commanded.Subscriptions

  import Pipeline

  def before_dispatch(%Pipeline{} = pipeline), do: pipeline

  def after_dispatch(%Pipeline{consistency: :eventual} = pipeline), do: pipeline
  def after_dispatch(%Pipeline{consistency: :strong, assigns: %{aggregate_uuid: aggregate_uuid, aggregate_version: aggregate_version}} = pipeline) do
    case Subscriptions.wait_for(aggregate_uuid, aggregate_version) do
      :ok ->
        pipeline

      {:error, :timeout} ->
        Logger.warn(fn -> "Consistency timeout waiting for aggregate \"#{inspect aggregate_uuid}\" at version #{inspect aggregate_version}" end)
        respond(pipeline, {:error, :consistency_timeout})
    end
  end

  def after_failure(%Pipeline{} = pipeline), do: pipeline
end
