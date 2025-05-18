defmodule Commanded.Serialization.Serializer do
  @moduledoc """
  Specification of a generic serializer.
  """

  @type t :: module
  @type config :: Keyword.t()

  @doc """
  Serialize the given term.
  """
  @callback serialize(any) :: binary | map

  @doc """
  Deserialize the given data to the corresponding term.
  """
  @callback deserialize(binary | map, config) :: any
end
