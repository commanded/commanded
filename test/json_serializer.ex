defmodule EventStore.JsonSerializer do
  @moduledoc """
  A serializer that uses the JSON format.
  """

  @behaviour EventStore.Serializer

  @doc """
  Serialize given term to JSON binary data.
  """
  def serialize(term) do
    Poison.encode!(term)
  end

  @doc """
  Deserialize given JSON binary data to the expected type.
  """
  def deserialize(binary, type) do
    Poison.decode!(binary, as: type)
  end
end
