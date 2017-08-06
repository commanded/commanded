defmodule EventStore.Storage.Initializer do
  alias EventStore.Sql.Statements

  def run!(conn) do
    Statements.initializers
    |> Enum.each(&(Postgrex.query!(conn, &1, [], pool: DBConnection.Poolboy)))
  end

  def reset!(conn) do
    Postgrex.query!(conn, Statements.truncate_tables, [], pool: DBConnection.Poolboy)
  end
end
