defmodule Commanded.ValidationMiddleware do
  @behaviour Commanded.Middleware

  alias Commanded.Middleware.Pipeline
  import Pipeline

  def before_dispatch(%Pipeline{} = pipeline) do
    %Pipeline{command: command} = pipeline

    case Map.get(command, :valid?, false) do
      true ->
        pipeline

      false ->
        pipeline
        |> respond({:error, :validation_failure, "validation failed"})
        |> halt()
    end
  end

  def after_dispatch(pipeline), do: pipeline
  def after_failure(pipeline), do: pipeline
end
