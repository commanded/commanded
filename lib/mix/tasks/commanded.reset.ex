defmodule Mix.Tasks.Commanded.Reset do
  @moduledoc """
  Reset an event handler.

  ## Example

      mix commanded.reset MyApp.MyEventHandler

  """

  use Mix.Task

  @shortdoc "Reset an event handler to its start_from"

  @doc false
  def run(args) do
    module = args |> List.first()

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
