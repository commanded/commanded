defmodule Commanded.ProcessManagers.ProcessManager do
  @moduledoc """
  Macro and behaviour to define a process manager
  """

  @type domain_event :: struct
  @type process_manager :: struct
  @type uuid :: String.t

  @doc """
  Is the process manager interested in the given command?
  """
  @callback interested?(domain_event) :: {:start, uuid} | {:continue, uuid} | false

  @doc """
  Process manager instance handles the domain event
  """
  @callback handle(process_manager, domain_event) :: process_manager

  defmacro __using__(fields: fields) do
    quote do
      @behaviour Commanded.ProcessManagers.ProcessManager

      import Kernel, except: [apply: 2]

      defstruct process_uuid: nil, commands: [], state: nil

      defmodule State do
        defstruct unquote(fields)
      end

      @doc """
      Create a new process manager struct given a unique identity
      """
      def new(process_uuid, %__MODULE__.State{} = state \\ %__MODULE__.State{}) do
        %__MODULE__{process_uuid: process_uuid, state: state}
      end

      # dispatch a command for the given process manager
      defp dispatch(%__MODULE__{commands: commands} = process_manager, command) do
        %__MODULE__{process_manager |
          commands: commands ++ [command]
        }
      end

      # Receives a single event and is used to mutate the process manager's internal state
      defp update(%__MODULE__{state: state} = process_manager, event) do
        state = __MODULE__.apply(state, event)

        %__MODULE__{process_manager |
          state: state
        }
      end
    end
  end
end
