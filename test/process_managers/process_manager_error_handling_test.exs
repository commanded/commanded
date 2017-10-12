defmodule Commanded.ProcessManager.ProcessManagerErrorHandlingTest do
  use Commanded.StorageCase

  alias Commanded.Helpers
  alias Commanded.Helpers.Wait
  alias Commanded.ProcessManagers.{ProcessRouter,ProcessManagerInstance}

  import Commanded.Assertions.EventAssertions

  defmodule ExampleAggregate do
    defstruct [status: nil]

    defmodule Commands do
      defmodule StartProcess, do: defstruct [:process_uuid, :status]
      defmodule AttemptProcess, do: defstruct [:process_uuid]
    end

    defmodule Events do
      defmodule ProcessStarted, do: defstruct [:process_uuid, :status]
    end

    alias Commands.{StartProcess,AttemptProcess}
    alias Events.{ProcessStarted,ProcessResumed}

    def execute(%ExampleAggregate{}, %StartProcess{process_uuid: process_uuid, status: status}) do
      %ProcessStarted{process_uuid: process_uuid, status: status}
    end

    def execute(%ExampleAggregate{}, %AttemptProcess{}), do: {:error, :failed}

    def apply(%ExampleAggregate{} = state, %ProcessStarted{status: status}), do: %ExampleAggregate{state | status: status}
  end

  alias ExampleAggregate.Commands.{StartProcess,AttemptProcess}
  alias ExampleAggregate.Events.{ProcessStarted}

  defmodule ExampleRouter do
    use Commanded.Commands.Router

    dispatch [StartProcess,AttemptProcess],
      to: ExampleAggregate, identity: :process_uuid
  end

  defmodule ErrorHandlingProcessManager do
    use Commanded.ProcessManagers.ProcessManager,
      name: "ErrorHandlingProcessManager",
      router: ExampleRouter

    defstruct [
      status_history: []
    ]

    alias ExampleAggregate.Events.ProcessStarted

    def interested?(%ProcessStarted{process_uuid: process_uuid}), do: {:start, process_uuid}

    def handle(%ErrorHandlingProcessManager{}, %ProcessStarted{process_uuid: process_uuid}) do
      %AttemptProcess{process_uuid: process_uuid}
    end

    def error({:error, :failed}, %ProcessStarted{}, %{attempts: attempts}) when attempts >= 3 do
      {:stop, :too_many_attempts}
    end

    def error({:error, :failed}, %ProcessStarted{}, %{command: command} = context) do
      attempts = Map.get(context, :attempts, 0)
      {:retry, Map.put(context, :attempts, attempts + 1)}
    end

    def apply(
      %ErrorHandlingProcessManager{status_history: status_history} = process,
      %ProcessStarted{status: status})
    do
      %ErrorHandlingProcessManager{process |
        status_history: status_history ++ [status]
      }
    end
  end

  test "should retry the event until process manager requests stop" do
    process_uuid = UUID.uuid4()

    {:ok, process_router} = ErrorHandlingProcessManager.start_link()
  end
end
