defmodule Commanded.Middleware.Logger do
  @moduledoc """
  A `Commanded.Middleware` that logs each stage of the command dispatch using
  the Elixir `Logger`:

  - Before dispatch.
  - After successful dispatch.
  - After failed dispatch.

  """
  @behaviour Commanded.Middleware

  alias Commanded.Middleware.Pipeline
  import Pipeline
  require Logger

  def before_dispatch(%Pipeline{} = pipeline) do
    Logger.info(fn -> "#{log_context(pipeline)} dispatch start" end)
    assign(pipeline, :started_at, DateTime.utc_now())
  end

  def after_dispatch(%Pipeline{} = pipeline) do
    Logger.info(fn ->
      "#{log_context(pipeline)} succeeded in #{formatted_diff(delta(pipeline))}"
    end)

    pipeline
  end

  def after_failure(%Pipeline{assigns: %{error: error, error_reason: error_reason}} = pipeline) do
    Logger.info(fn ->
      "#{log_context(pipeline)} failed #{inspect(error)} in #{formatted_diff(delta(pipeline))}, due to: #{inspect(error_reason)}"
    end)

    pipeline
  end

  def after_failure(%Pipeline{assigns: %{error: error}} = pipeline) do
    Logger.info(fn ->
      "#{log_context(pipeline)} failed #{inspect(error)} in #{formatted_diff(delta(pipeline))}"
    end)

    pipeline
  end

  def after_failure(%Pipeline{} = pipeline), do: pipeline

  defp delta(%Pipeline{assigns: %{started_at: started_at}}) do
    DateTime.diff(DateTime.utc_now(), started_at, :microsecond)
  end

  defp log_context(%Pipeline{command: command}) do
    "#{inspect(command.__struct__)}"
  end

  defp formatted_diff(diff) when diff > 1_000_000,
    do: [diff |> div(1_000_000) |> Integer.to_string(), "s"]

  defp formatted_diff(diff) when diff > 1_000,
    do: [diff |> div(1_000) |> Integer.to_string(), "ms"]

  defp formatted_diff(diff), do: [diff |> Integer.to_string(), "µs"]
end
