defmodule Commanded.ProcessManagers.ProcessManager do
  @moduledoc """
  Behaviour to define a process manager
  """

  @type domain_event :: struct
  @type command :: struct
  @type process_manager :: struct
  @type process_uuid :: String.t

  @doc """
  Is the process manager interested in the given command?
  """
  @callback interested?(domain_event) :: {:start, process_uuid} | {:continue, process_uuid} | false

  @doc """
  Process manager instance handles the domain event, returning commands to dispatch
  """
  @callback handle(process_manager, domain_event) :: list(command)

  @doc """
  Mutate the process manager's state by applying the domain event
  """
  @callback apply(process_manager, domain_event) :: process_manager
end
