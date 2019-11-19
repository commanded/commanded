defmodule Commanded.Middleware.ExtractAggregateIdentity do
  @moduledoc """
  An internal `Commanded.Middleware` that extracts the target aggregate's
  identity from the command.
  """

  @behaviour Commanded.Middleware

  alias Commanded.Middleware.Pipeline
  import Pipeline

  def before_dispatch(%Pipeline{} = pipeline) do
    with aggregate_uuid when aggregate_uuid not in [nil, ""] <- extract_aggregate_uuid(pipeline),
         aggregate_uuid when is_binary(aggregate_uuid) <- identity_to_string(aggregate_uuid),
         aggregate_uuid when is_binary(aggregate_uuid) <- prefix(aggregate_uuid, pipeline) do
      assign(pipeline, :aggregate_uuid, aggregate_uuid)
    else
      nil ->
        pipeline
        |> respond({:error, :invalid_aggregate_identity})
        |> halt()

      {:error, _error} = response ->
        pipeline
        |> respond(response)
        |> halt()
    end
  end

  def after_dispatch(%Pipeline{} = pipeline), do: pipeline

  def after_failure(%Pipeline{} = pipeline), do: pipeline

  # Extract identity using a field in the command.
  defp extract_aggregate_uuid(%Pipeline{command: command, identity: identity})
       when is_atom(identity) do
    Map.get(command, identity)
  end

  # Extract identity using a user defined function.
  defp extract_aggregate_uuid(%Pipeline{command: command, identity: identity})
       when is_function(identity, 1) do
    identity.(command)
  end

  defp extract_aggregate_uuid(%Pipeline{}), do: {:error, :invalid_aggregate_identity}

  # Attempt to convert the aggregate identity to a string via the `String.Chars` protocol.
  defp identity_to_string(aggregate_uuid) do
    try do
      to_string(aggregate_uuid)
    rescue
      Protocol.UndefinedError ->
        {:error, {:unsupported_aggregate_identity_type, aggregate_uuid}}
    end
  end

  # No aggregate identity prefix.
  defp prefix(aggregate_uuid, %Pipeline{identity_prefix: identity_prefix})
       when identity_prefix in [nil, ""],
       do: aggregate_uuid

  # Extract identity prefix using a user defined function.
  defp prefix(aggregate_uuid, %Pipeline{identity_prefix: identity_prefix})
       when is_function(identity_prefix, 0) do
    identity_prefix.() <> aggregate_uuid
  end

  # Identity prefix is a string to prepend to aggregate identity.
  defp prefix(aggregate_uuid, %Pipeline{identity_prefix: identity_prefix})
       when is_binary(identity_prefix),
       do: identity_prefix <> aggregate_uuid

  defp prefix(_aggregate_uuid, %Pipeline{}), do: {:error, :invalid_aggregate_identity_prefix}
end
