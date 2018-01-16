defmodule Commanded.Middleware.ExtractAggregateIdentity do
  @moduledoc """
  A `Commanded.Middleware` that extracts the target aggregate's identity from
  the command.
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
        assign(pipeline, :aggregate_uuid, prefix(aggregate_uuid, pipeline))
    end
  end

  def after_dispatch(%Pipeline{} = pipeline), do: pipeline

  def after_failure(%Pipeline{} = pipeline), do: pipeline

  # extract identity using a user defined function
  defp extract_aggregate_uuid(%Pipeline{command: command, identity: identity})
       when is_function(identity) do
    identity.(command)
  end

  # extract identity using a field in the command
  defp extract_aggregate_uuid(%Pipeline{command: command, identity: identity})
       when is_atom(identity) do
    Map.get(command, identity)
  end

  defp prefix(aggregate_uuid, %Pipeline{identity_prefix: nil}), do: aggregate_uuid

  # extract identity using a user defined function
  defp prefix(aggregate_uuid, %Pipeline{identity_prefix: identity_prefix})
       when is_function(identity_prefix) do
    identity_prefix.() <> aggregate_uuid
  end

  defp prefix(aggregate_uuid, %Pipeline{identity_prefix: identity_prefix}),
    do: identity_prefix <> aggregate_uuid
end
