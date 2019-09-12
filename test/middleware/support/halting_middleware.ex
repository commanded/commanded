defmodule Commanded.HaltingMiddleware do
  @behaviour Commanded.Middleware

  import Commanded.Middleware.Pipeline

  def before_dispatch(pipeline) do
    halt(pipeline)
  end

  def after_dispatch(pipeline), do: pipeline
  def after_failure(pipeline), do: pipeline
end
