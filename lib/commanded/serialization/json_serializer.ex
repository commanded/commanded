if Code.ensure_loaded?(Jason) do
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
      Jason.encode!(term)
    end

    @doc """
    Deserialize given JSON binary data to the expected type.
    """
    def deserialize(binary, config \\ [])

    def deserialize(binary, config) do
      type =
        case Keyword.get(config, :type) do
          nil -> nil
          type -> TypeProvider.to_struct(type)
        end

      opts =
        case Keyword.get(config, :type) do
          nil -> %{}
          _type -> %{keys: :atoms}
        end

      # todo this actually should be with ! since it can throw
      res =
        binary
        |> Jason.decode!(opts)
        |> JsonDecoder.decode()

      if type !== nil, do: struct(type, res), else: res
    end
  end
end
