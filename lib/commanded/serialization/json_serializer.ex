defmodule Commanded.Serialization.JsonSerializer do
  @moduledoc """
  A serializer that uses the JSON format.
  """

  @behaviour Commanded.EventStore.Serializer

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
  def deserialize(binary, config) do
    type = case Keyword.get(config, :type, nil) do
      nil -> nil
      type -> to_event_type(type)
    end

    binary
    |> Poison.decode!(as: type)
    |> JsonDecoder.decode()
  end

  def to_event_name(module) do
    Atom.to_string(module)
  end

  defp to_event_type(type) do
    type |> String.to_existing_atom() |> struct()
  end
end
