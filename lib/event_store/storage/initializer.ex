defmodule EventStore.Storage.Initializer do
  @moduledoc false
  alias EventStore.Sql.Statements

  def run!(conn), do: execute(conn, Statements.initializers())

  def reset!(conn), do: execute(conn, Statements.reset())

  defp execute(conn, statements) do
    Enum.each(statements, &(Postgrex.query!(conn, &1, [], pool: DBConnection.Poolboy)))
  end
end
