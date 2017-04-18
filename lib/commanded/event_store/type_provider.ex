defmodule Commanded.EventStore.TypeProvider do
  @moduledoc """
  Specification to convert between an Elixir struct and a corresponding string type.
  """

  defmacro __using__(_) do
    type_provider = Application.get_env(:commanded, :type_provider, Commanded.Serialization.ModuleNameTypeProvider)

    quote do
      @type_provider unquote type_provider
    end
  end

  @type t :: module

  @type type :: String.t

  @doc """
  Type of the given Elixir struct as a string
  """
  @callback to_string(struct) :: type

  @doc """
  Convert the given type string to an Elixir struct
  """
  @callback to_struct(type) :: struct
end
