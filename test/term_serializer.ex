defmodule EventStore.TermSerializer do
  @behaviour EventStore.Serializer

  @doc """
  Serialize given Erlang term to binary using Erlang's External Term Format (http://erlang.org/doc/apps/erts/erl_ext_dist.html).
  """
  def serialize(term) do
    :erlang.term_to_binary(term)
  end

  @doc """
  Deserialize given binary data to an Erlang term using Erlang's External Term Format (http://erlang.org/doc/apps/erts/erl_ext_dist.html).
  """
  def deserialize(binary) do
    :erlang.binary_to_term(binary, [:safe])
  end
end
