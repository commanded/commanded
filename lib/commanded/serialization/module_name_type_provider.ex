defmodule Commanded.Serialization.ModuleNameTypeProvider do
  @moduledoc """
  A type provider that uses the Elixir module name

  Example:

    - %An.Event{} module mapped to "Elixir.An.Event".
  """

  @behaviour Commanded.EventStore.TypeProvider

  def to_string(struct) when is_map(struct), do: Atom.to_string(struct.__struct__)

  def to_struct(type) do
    type |> String.to_existing_atom() |> struct()
  end
end
