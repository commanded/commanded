defmodule Mix.Tasks.Commanded.Reset do
  @moduledoc """
  Reset an event handler.

  ## Usage

      mix commanded.reset --app <app> --handler <handler_name>

  ## Examples

      mix commanded.reset --app MyApp --handler MyHandler
      mix commanded.reset -a MyApp -h MyHandler

  ## Command line options

    * `-a`, `--app` - the Commanded application
    * `-h`, `--handler` - the name of the event handler to reset
    * `-q`, `--quiet` - do not log output

  """

  use Mix.Task

  alias Commanded.Event.Handler
  alias Commanded.Registration

  @shortdoc "Reset an event handler to its start_from"

  @switches [
    app: :string,
    handler: :string,
    quiet: :boolean
  ]

  @aliases [
    a: :app,
    h: :handler,
    q: :quiet
  ]

  @doc false
  def run(args) do
    {parsed, _args} = OptionParser.parse!(args, strict: @switches, aliases: @aliases)

    app = Keyword.get(parsed, :app)
    handler = Keyword.get(parsed, :handler)

    unless app && handler do
      Mix.raise("""
      Reset requires an application and handler, use "mix commanded.reset --app <app> --handler <handler>"
      """)
    end

    app = String.to_atom("Elixir." <> app)

    reset(app, handler, parsed)
  end

  defp reset(app, handler_name, opts) do
    case app.start_link() do
      {:ok, _pid} ->
        :ok

      {:error, {:already_started, _pid}} ->
        :ok

      {:error, error} ->
        Mix.raise("Failed to start " <> inspect(app) <> " due to: " <> inspect(error))
    end

    quiet = Keyword.get(opts, :quiet, false)
    registry_name = Handler.name(app, handler_name)

    case Registration.whereis_name(app, registry_name) do
      :undefined ->
        unless quiet, do: Mix.shell().info("No process found for #{inspect(handler_name)}")

      pid ->
        unless quiet, do: Mix.shell().info("Resetting #{inspect(handler_name)}")
        send(pid, :reset)
    end
  end
end
