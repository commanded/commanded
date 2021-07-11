defmodule Commanded.UUIDGenerator.IdDynamicMiddleware do
  @behaviour Commanded.Middleware

  alias Commanded.Middleware.Pipeline

  alias Commanded.UUIDGenerator.IdDynamicApp

  def before_dispatch(%Pipeline{} = pipeline) do
    %Pipeline{command: command} = pipeline

    stuff_id = Map.fetch!(command, :stuff_id)
    application = IdDynamicApp.app_name(stuff_id)

    %Pipeline{pipeline | application: application}
  end

  def before_dispatch(pipeline), do: pipeline

  def after_dispatch(pipeline), do: pipeline
  def after_failure(pipeline), do: pipeline
end
