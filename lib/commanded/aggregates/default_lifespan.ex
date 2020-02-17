defmodule Commanded.Aggregates.DefaultLifespan do
  @moduledoc """
  The default implementation of the `Commanded.Aggregates.AggregateLifespan`
  behaviour.

  It will ensure that an aggregate instance process runs indefinitely once
  started, unless an exception is encountered.
  """

  @behaviour Commanded.Aggregates.AggregateLifespan

  @doc """
  Aggregate will run indefinitely once started.
  """
  def after_event(_event), do: :infinity

  @doc """
  Aggregate will run indefinitely once started.
  """
  def after_command(_command), do: :infinity

  @doc """
  Aggregate is stopped on exception, but will run indefinitely for any non-
  exception error.
  """
  def after_error(error) do
    if Exception.exception?(error) do
      {:stop, error}
    else
      :infinity
    end
  end
end
