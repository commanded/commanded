defmodule Commanded.Aggregates.DefaultLifespan do
  @moduledoc """
  The default implementation of the `Commanded.Aggregates.AggregateLifespan`
  behaviour.

  It will ensure that an aggregate instance process runs indefinitely once
  started.
  """

  @behaviour Commanded.Aggregates.AggregateLifespan

  @doc """
  Aggregate will run indefinitely once started.
  """
  def after_event(_event), do: :infinity
end
