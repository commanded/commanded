defmodule Commanded.Serialization.JsonSerializer do
  @moduledoc """
  A serializer that uses the JSON format.
  """

  alias Commanded.EventStore.TypeProvider
  alias Commanded.Serialization.JsonDecoder

  @doc """
  Serialize given term to JSON binary data.
  """
  def serialize(term) do
    Poison.encode!(term)
  end

  @doc """
  Deserialize given JSON binary data to the expected type.
  """
  def deserialize(binary, config \\ [])
  def deserialize(binary, config) do
    type = case Keyword.get(config, :type) do
      nil -> nil
      type -> TypeProvider.to_struct(type)
    end

    binary
    |> Poison.decode!(as: type)
    |> JsonDecoder.decode()
  end
end
