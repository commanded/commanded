defmodule Commanded.UUIDGenerator.IdMiddleware do
  use Agent

  @behaviour Commanded.Middleware
  alias Commanded.Middleware.Pipeline

  def start_link(_opts) do
    Agent.start_link(fn -> {nil, nil} end, name: __MODULE__)
  end

  def before_fields() do
    Agent.get(__MODULE__, &elem(&1, 0))
  end

  def after_fields() do
    Agent.get(__MODULE__, &elem(&1, 1))
  end

  defp uuid_fields(%Pipeline{} = pipeline) do
    Map.take(pipeline, [:correlation_id, :command_uuid, :event_id])
  end

  def before_dispatch(%Pipeline{} = pipeline) do
    Agent.update(__MODULE__, fn {_before, next} -> {uuid_fields(pipeline), next} end)

    pipeline
  end

  def before_dispatch(pipeline), do: pipeline

  def after_dispatch(%Pipeline{} = pipeline) do
    Agent.update(__MODULE__, fn {before, _next} -> {before, uuid_fields(pipeline)} end)

    pipeline
  end

  def after_dispatch(pipeline), do: pipeline

  def after_failure(pipeline), do: pipeline
end
