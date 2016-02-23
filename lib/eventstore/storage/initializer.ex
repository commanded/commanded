defmodule EventStore.Storage.Initializer do
  require Logger

  alias EventStore.Sql.Statements

  def run!(conn) do
    Logger.info "initialize storage"

    Statements.initializers
    |> Enum.each(&(Postgrex.query!(conn, &1, [])))

    Logger.info "storage available"
  end
end
