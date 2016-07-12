defmodule EventStore.Serializer do
  @moduledoc """
  Specification of a serializer to convert between an Elixir term and binary data.
  """

  @callback serialize(any) :: binary
  @callback deserialize(binary) :: any
end
