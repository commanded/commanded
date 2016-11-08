defmodule Commanded.Helpers.CommandAuditMiddleware do
  @behaviour Commanded.Middleware

  defmodule AuditLog do
    defstruct [
      dispatched: [],
      succeeded: [],
      failed: [],
    ]
  end

  def start_link do
    Agent.start_link(fn -> %AuditLog{} end, name: __MODULE__)
  end

  def before_dispatch(%{command: command} = pipeline) do
    Agent.update(__MODULE__, fn %AuditLog{dispatched: dispatched} = audit ->
      %AuditLog{audit | dispatched: dispatched ++ [command]}
    end)

    pipeline
  end

  def after_dispatch(%{command: command} = pipeline) do
    Agent.update(__MODULE__, fn %AuditLog{succeeded: succeeded} = audit ->
      %AuditLog{audit | succeeded: succeeded ++ [command]}
    end)

    pipeline
  end

  def after_failure(%{command: command} = pipeline) do
    Agent.update(__MODULE__, fn %AuditLog{failed: failed} = audit ->
      %AuditLog{audit | failed: failed ++ [command]}
    end)

    pipeline
  end

  @doc """
  Access the dispatched commands the middleware received
  """
  def dispatched_commands do
    Agent.get(__MODULE__, fn %AuditLog{dispatched: dispatched} -> dispatched end)
  end

  @doc """
  Access the dispatched commands that successfully executed
  """
  def succeeded_commands do
    Agent.get(__MODULE__, fn %AuditLog{succeeded: succeeded} -> succeeded end)
  end

  @doc """
  Access the dispatched commands that failed to execute
  """
  def failed_commands do
    Agent.get(__MODULE__, fn %AuditLog{failed: failed} -> failed end)
  end
end
