if Code.ensure_loaded?(Jason) do
  defmodule Commanded.Serialization.JsonSerializer do
    @moduledoc """
    A serializer that uses the JSON format and Jason library.
    """

    alias Commanded.EventStore.TypeProvider
    alias Commanded.Serialization.JsonDecoder

    @doc """
    Serialize given term to JSON binary data.
    """
    def serialize(term, config \\ []) do
      options = maybe_options(config)
      Jason.encode!(term, options)
    end

    @doc """
    Deserialize given JSON binary data to the expected type.
    """
    def deserialize(binary, config \\ []) do
      type = maybe_type(config)

      options =
        case type do
          nil -> %{}
          _type -> %{keys: :atoms} |> Map.merge(maybe_options(config))
        end

      binary
      |> Jason.decode!(options)
      |> to_struct(type)
      |> JsonDecoder.decode()
    end

    defp to_struct(data, nil), do: data
    defp to_struct(data, struct), do: struct(struct, data)

    defp maybe_options(config) do
      case Keyword.get(config, :options) do
        nil -> %{}
        options -> options
      end
    end

    defp maybe_type(config) do
      case Keyword.get(config, :type) do
        nil -> nil
        type -> TypeProvider.to_struct(type)
      end
    end
  end

  require Protocol

  Protocol.derive(Jason.Encoder, Commanded.EventStore.SnapshotData)
end
