defmodule Mix.Tasks.Commanded.Reset do
  @moduledoc """
  Reset an event handler.

  ## Examples
      mix commanded.reset MyApp.MyEventHandler
  """

  use Mix.Task
  # import Mix.EventStore

  # alias EventStore.Tasks.Init

  @shortdoc "Reset an event handler to its start_from"

  @switches [
  ]

  @aliases [
  ]

  @doc false
  def run(args) do
    module = args |> List.first

    {:ok, _} = Application.ensure_all_started(:commanded)

    case Commanded.Registration.whereis_name({Commanded.Event.Handler, module}) do
      :undefined ->
        IO.puts("No process found for #{module}")
      pid ->
        IO.puts("Resetting #{module}")
        send(pid, :reset)
    end
  end
end
