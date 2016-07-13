defmodule EventStore.Serializer do
  @moduledoc """
  Specification of a serializer to convert between an Elixir term and binary data.
  """

  @doc """
  Serialize the given term to a binary representation
  """
  @callback serialize(any) :: binary

  @doc """
  Deserialize the given binary data to the corresponding term
  """
  @callback deserialize(binary, map) :: any
end
