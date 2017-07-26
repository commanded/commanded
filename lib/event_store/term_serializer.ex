defmodule EventStore.TermSerializer do
  @moduledoc """
  A serializer that uses Erlang's external term format (http://erlang.org/doc/apps/erts/erl_ext_dist.html)
  """

  @behaviour EventStore.Serializer

  @doc """
  Serialize given term to binary data.
  """
  def serialize(term) do
    :erlang.term_to_binary(term)
  end

  @doc """
  Deserialize given binary data in Erlang's external term format.
  """
  def deserialize(binary, _config) do
    :erlang.binary_to_term(binary)
  end
end
