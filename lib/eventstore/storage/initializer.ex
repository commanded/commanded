defmodule EventStore.Storage.Initializer do
  alias EventStore.Sql.Statements

  def run!(conn) do
    Statements.initializers
    |> Enum.each(&(Postgrex.query!(conn, &1, [])))
  end
end
