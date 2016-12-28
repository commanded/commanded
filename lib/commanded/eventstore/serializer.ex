defmodule Commanded.EventStore.Serializer do

  defmacro __using__(_) do
    quote do
      @serializer Keyword.get(
	Application.get_env(:commanded, :extreme),
	:serializer,
	Commanded.Serialization.JsonSerializer
      )
    end
  end
  
  @moduledoc """
  Specification of a serializer to convert between an Elixir term and binary data.
  """

  @type t :: module

  @type config :: Keyword.t

  @doc """
  Serialize given struct type to a binary representation
  """
  @callback to_event_name(module) :: binary

  @doc """
  Serialize the given term to a binary representation
  """
  @callback serialize(any) :: binary

  @doc """
  Deserialize the given binary data to the corresponding term
  """
  @callback deserialize(binary, config) :: any

end
