defmodule Mix.Tasks.EventStore.Create do
  use Mix.Task

  alias EventStore.Storage
  alias EventStore.Storage.Database

  @shortdoc "Create the database for the EventStore"

  @moduledoc """
  Create the database for the EventStore.

  ## Examples

      mix event_store.create

  ## Command line options

    * `--no-compile` - do not compile before creating
    * `--quiet` - do no log output

  """

  @doc false
  def run(_args) do
    Application.ensure_all_started(:postgrex)

    config = Application.get_env(:eventstore, Storage)

    create_database(config)

    Mix.Task.reenable "event_store.create"
  end

  defp create_database(config) do
    case Database.create(config) do
      :ok ->
        Mix.shell.info "The EventStore database has been created."
        initialize_storage(config)
      {:error, :already_up} -> Mix.shell.info "The EventStore database already exists."
      {:error, term} when is_binary(term) -> Mix.raise "The EventStore database couldn't be created, reason given: #{term}."
      {:error, term} -> Mix.raise "The EventStore database couldn't be created, reason given: #{inspect term}."
    end
  end

  defp initialize_storage(config) do
    {:ok, conn} = Postgrex.start_link(config)
    
    Storage.Initializer.run!(conn)
  end
end
