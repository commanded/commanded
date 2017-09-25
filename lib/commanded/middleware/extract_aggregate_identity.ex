defmodule Commanded.Middleware.ExtractAggregateIdentity do
  @moduledoc """
  A `Commanded.Middleware` that extracts the target aggregate's identity from the command
  """

  @behaviour Commanded.Middleware

  alias Commanded.Middleware.Pipeline
  import Pipeline

  def before_dispatch(%Pipeline{} = pipeline) do
    case extract_aggregate_uuid(pipeline) do
      nil ->
        pipeline
        |> respond({:error, :invalid_aggregate_identity})
        |> halt()

      aggregate_uuid ->
        assign(pipeline, :aggregate_uuid, aggregate_uuid)
    end
  end

  def after_dispatch(%Pipeline{} = pipeline), do: pipeline

  def after_failure(%Pipeline{} = pipeline), do: pipeline

  defp extract_aggregate_uuid(%Pipeline{command: command, identity: identity}) do
    Map.get(command, identity)
  end
end
