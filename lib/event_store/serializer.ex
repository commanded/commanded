defmodule EventStore.Serializer do
  @moduledoc """
  Specification of a serializer to convert between an Elixir term and binary data.
  """

  @type t :: module

  @type config :: Keyword.t

  @doc """
  Serialize the given term to a binary representation
  """
  @callback serialize(any) :: binary

  @doc """
  Deserialize the given binary data to the corresponding term
  """
  @callback deserialize(binary, config) :: any

  @doc """
  Include the configured serializer as a module attribute
  """
  defmacro __using__(_) do
    config = Application.get_env(:eventstore, EventStore.Storage, [])
    serializer = config[:serializer] || raise "EventStore expects :serializer to be configured in environment"

    quote do
      @serializer unquote(serializer)
    end
  end
end
