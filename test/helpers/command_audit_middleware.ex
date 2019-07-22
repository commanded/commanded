defmodule Commanded.Helpers.CommandAuditMiddleware do
  @moduledoc false

  @behaviour Commanded.Middleware

  defmodule AuditLog do
    @moduledoc false

    defstruct dispatched: [],
              succeeded: [],
              failed: []
  end

  def child_spec(_opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, []},
      type: :worker,
      restart: :permanent,
      shutdown: 5_000
    }
  end

  def start_link do
    Agent.start_link(fn -> %AuditLog{} end, name: __MODULE__)
  end

  def before_dispatch(pipeline) do
    Agent.update(__MODULE__, fn %AuditLog{dispatched: dispatched} = audit ->
      %AuditLog{audit | dispatched: dispatched ++ [pipeline]}
    end)

    pipeline
  end

  def after_dispatch(pipeline) do
    Agent.update(__MODULE__, fn %AuditLog{succeeded: succeeded} = audit ->
      %AuditLog{audit | succeeded: succeeded ++ [pipeline]}
    end)

    pipeline
  end

  def after_failure(pipeline) do
    Agent.update(__MODULE__, fn %AuditLog{failed: failed} = audit ->
      %AuditLog{audit | failed: failed ++ [pipeline]}
    end)

    pipeline
  end

  def reset do
    Agent.update(__MODULE__, fn _ -> %AuditLog{} end)
  end

  @doc """
  Get the counts of the dispatched, succeeded, and failed commands
  """
  def count_commands do
    Agent.get(__MODULE__, fn %AuditLog{
                               dispatched: dispatched,
                               succeeded: succeeded,
                               failed: failed
                             } ->
      {length(dispatched), length(succeeded), length(failed)}
    end)
  end

  @doc """
  Access the dispatched commands the middleware received
  """
  def dispatched_commands(pluck \\ & &1.command) do
    Agent.get(__MODULE__, fn %AuditLog{dispatched: dispatched} ->
      dispatched |> Enum.map(pluck)
    end)
  end

  @doc """
  Access the dispatched commands that successfully executed
  """
  def succeeded_commands do
    Agent.get(__MODULE__, fn %AuditLog{succeeded: succeeded} ->
      succeeded |> Enum.map(& &1.command)
    end)
  end

  @doc """
  Access the dispatched commands that failed to execute
  """
  def failed_commands do
    Agent.get(__MODULE__, fn %AuditLog{failed: failed} ->
      failed |> Enum.map(& &1.command)
    end)
  end
end
