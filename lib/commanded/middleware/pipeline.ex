defmodule Commanded.Middleware.Pipeline do
  @moduledoc """
  Pipeline is a struct used as an argument in the callback functions of modules implementing the `Commanded.Middleware` behaviour.
  This struct must be returned by each function to be used in the next middleware based on the configured middleware chain.
  """

  defstruct [
    assigns: %{},
    command: nil,
    halted: false,
    terminated: false,
  ]

  alias Commanded.Middleware.Pipeline

  @doc """
  Puts the `key` with value equal to `value` into `assigns` map
  """
  def assign(%Pipeline{assigns: assigns} = pipeline, key, value) when is_atom(key) do
    %Pipeline{pipeline | assigns: Map.put(assigns, key, value)}
  end

  @doc """
  Sets `halted` to true
  """
  def halt(%Pipeline{} = pipeline) do
    %Pipeline{pipeline | halted: true}
  end

  @doc """
  Sets `terminated` to true
  """
  def terminate(%Pipeline{} = pipeline) do
    %Pipeline{pipeline | terminated: true}
  end

  @doc """
  Implements the middleware chain
  """
  def chain(pipeline, stage, middleware)
  def chain(pipeline, _stage, []), do: pipeline
  def chain(%Pipeline{halted: true} = pipeline, _stage, _middleware), do: pipeline
  def chain(%Pipeline{terminated: true} = pipeline, _stage, _middleware), do: pipeline
  def chain(pipeline, stage, [module | modules]) do
    chain(apply(module, stage, [pipeline]), stage, modules)
  end
end
