defmodule Mix.Tasks.EventStore.Drop do
  @moduledoc """
  Drop the database for the EventStore.

  ## Examples

      mix event_store.drop

  """

  use Mix.Task

  alias EventStore.Storage
  alias EventStore.Storage.Database

  @shortdoc "Drop the database for the EventStore"
  
  @doc false
  def run(_args) do
    config = EventStore.Config.parse Application.get_env(:eventstore, Storage)

    if skip_safety_warnings?() or Mix.shell.yes?("Are you sure you want to drop the EventStore database?") do
      drop_database(config)
    end
  end

  defp skip_safety_warnings? do
    Mix.Project.config[:start_permanent] != true
  end

  defp drop_database(config) do
    case Database.drop(config) do
      :ok -> Mix.shell.info "The EventStore database has been dropped."
      {:error, :already_down} -> Mix.shell.info "The EventStore database has already been dropped."
      {:error, term} -> Mix.raise "The EventStore database couldn't be dropped, reason given: #{inspect term}."
    end
  end
end
