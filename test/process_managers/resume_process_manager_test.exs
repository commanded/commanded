defmodule Commanded.ProcessManager.ResumeProcessManagerTest do
  use Commanded.StorageCase

  alias Commanded.Helpers
  alias Commanded.Helpers.Wait
  alias Commanded.ProcessManagers.{ProcessRouter,ProcessManagerInstance}

  import Commanded.Assertions.EventAssertions

  defmodule ExampleAggregate do
    defstruct [status: nil]

    defmodule Commands do
      defmodule StartProcess, do: defstruct [process_uuid: nil, status: nil]
      defmodule ResumeProcess, do: defstruct [process_uuid: nil, status: nil]
    end

    defmodule Events do
      defmodule ProcessStarted, do: defstruct [process_uuid: nil, status: nil]
      defmodule ProcessResumed, do: defstruct [process_uuid: nil, status: nil]
    end

    alias Commands.{StartProcess,ResumeProcess}
    alias Events.{ProcessStarted,ProcessResumed}

    def start_process(%ExampleAggregate{}, %StartProcess{process_uuid: process_uuid, status: status}) do
      %ProcessStarted{process_uuid: process_uuid, status: status}
    end

    def resume_process(%ExampleAggregate{}, %ResumeProcess{process_uuid: process_uuid, status: status}) do
      %ProcessResumed{process_uuid: process_uuid, status: status}
    end

    # state mutatators

    def apply(%ExampleAggregate{} = state, %ProcessStarted{status: status}), do: %ExampleAggregate{state | status: status}
    def apply(%ExampleAggregate{} = state, %ProcessResumed{status: status}), do: %ExampleAggregate{state | status: status}
  end

  alias ExampleAggregate.Commands.{StartProcess,ResumeProcess}
  alias ExampleAggregate.Events.{ProcessStarted,ProcessResumed}

  defmodule CommandHandler do
    @behaviour Commanded.Commands.Handler

    def handle(%ExampleAggregate{} = aggregate, %StartProcess{} = start_process) do
      aggregate
      |> ExampleAggregate.start_process(start_process)
    end

    def handle(%ExampleAggregate{} = aggregate, %ResumeProcess{} = resume_process) do
      aggregate
      |> ExampleAggregate.resume_process(resume_process)
    end
  end

  defmodule ExampleRouter do
    use Commanded.Commands.Router

    dispatch StartProcess, to: CommandHandler, aggregate: ExampleAggregate, identity: :process_uuid
    dispatch ResumeProcess, to: CommandHandler, aggregate: ExampleAggregate, identity: :process_uuid
  end

  defmodule ExampleProcessManager do
    use Commanded.ProcessManagers.ProcessManager,
      name: "example-process-manager",
      router: ExampleRouter

    defstruct [
      status_history: []
    ]

    alias ExampleAggregate.Events.ProcessStarted

    def interested?(%ProcessStarted{process_uuid: process_uuid}), do: {:start, process_uuid}
    def interested?(%ProcessResumed{process_uuid: process_uuid}), do: {:continue, process_uuid}
    def interested?(_event), do: false

    def handle(%ExampleProcessManager{}, %ProcessStarted{}), do: []
    def handle(%ExampleProcessManager{}, %ProcessResumed{}), do: []

    ## state mutators

    def apply(%ExampleProcessManager{status_history: status_history} = process, %ProcessStarted{status: status}) do
      %ExampleProcessManager{process |
        status_history: status_history ++ [status]
      }
    end

    def apply(%ExampleProcessManager{status_history: status_history} = process, %ProcessResumed{status: status}) do
      %ExampleProcessManager{process |
        status_history: status_history ++ [status]
      }
    end
  end

  test "should resume a process manager with same state when process restarts" do
    process_uuid = UUID.uuid4

    {:ok, process_router} = ExampleProcessManager.start_link()

    # transfer funds between account 1 and account 2
    :ok = ExampleRouter.dispatch(%StartProcess{process_uuid: process_uuid, status: "start"})

    assert_receive_event ProcessStarted, fn event ->
      assert event.process_uuid == process_uuid
      assert event.status == "start"
    end

    :timer.sleep 100

    # wait for process instance to receive event
    Wait.until(fn ->
      process_instance = ProcessRouter.process_instance(process_router, process_uuid)
      %{status_history: ["start"]} = ProcessManagerInstance.process_state(process_instance)
    end)

    Helpers.Process.shutdown(process_router)

    # wait for subscription to receive DOWN notification and remove subscription's PID
    :timer.sleep(1_000)

    {:ok, process_router} = ExampleProcessManager.start_link()

    :ok = ExampleRouter.dispatch(%ResumeProcess{process_uuid: process_uuid, status: "resume"})

    wait_for_event(ProcessResumed, fn event -> event.process_uuid == process_uuid end)

    case ProcessRouter.process_instance(process_router, process_uuid) do
      {:error, :process_manager_not_found} -> flunk("process state not available")
      process_instance ->
        state = ProcessManagerInstance.process_state(process_instance)
        assert state.status_history == ["start", "resume"]
    end
  end
end
