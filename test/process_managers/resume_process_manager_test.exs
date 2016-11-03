defmodule Commanded.ProcessManager.ResumeProcessManagerTest do
  use Commanded.StorageCase

  alias Commanded.Helpers
  alias Commanded.Helpers.Wait
  alias Commanded.ProcessManagers.ProcessRouter

  import Commanded.Assertions.EventAssertions

  defmodule ExampleAggregate do
    use EventSourced.AggregateRoot, fields: [status: nil]

    defmodule Commands do
      defmodule StartProcess do
        defstruct process_uuid: UUID.uuid4, status: nil
      end

      defmodule ResumeProcess do
        defstruct process_uuid: UUID.uuid4, status: nil
      end
    end

    defmodule Events do
      defmodule ProcessStarted do
        defstruct process_uuid: nil, status: nil
      end

      defmodule ProcessResumed do
        defstruct process_uuid: nil, status: nil
      end
    end

    alias Commands.{StartProcess,ResumeProcess}
    alias Events.{ProcessStarted,ProcessResumed}

    def start_process(%ExampleAggregate{} = aggregate, %StartProcess{process_uuid: process_uuid, status: status}) do
      aggregate =
        aggregate
        |> update(%ProcessStarted{process_uuid: process_uuid, status: status})

      {:ok, aggregate}
    end

    def resume_process(%ExampleAggregate{} = aggregate, %ResumeProcess{process_uuid: process_uuid, status: status}) do
      aggregate =
        aggregate
        |> update(%ProcessResumed{process_uuid: process_uuid, status: status})

      {:ok, aggregate}
    end

    # state mutatators

    def apply(%ExampleAggregate.State{} = state, %ProcessStarted{status: status}) do
      %ExampleAggregate.State{state |
        status: status
      }
    end

    def apply(%ExampleAggregate.State{} = state, %ProcessResumed{status: status}) do
      %ExampleAggregate.State{state |
        status: status
      }
    end
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
    use Commanded.ProcessManagers.ProcessManager, fields: [
      status_history: []
    ]

    alias ExampleAggregate.Events.ProcessStarted

    def interested?(%ProcessStarted{process_uuid: process_uuid}), do: {:start, process_uuid}
    def interested?(%ProcessResumed{process_uuid: process_uuid}), do: {:continue, process_uuid}
    def interested?(_event), do: false

    def handle(%ExampleProcessManager{} = process, %ProcessStarted{} = process_started) do
      {:ok, update(process, process_started)}
    end

    def handle(%ExampleProcessManager{} = process, %ProcessResumed{} = process_resumed) do
      {:ok, update(process, process_resumed)}
    end

    ## state mutators

    def apply(%ExampleProcessManager.State{status_history: status_history} = process, %ProcessStarted{status: status}) do
      %ExampleProcessManager.State{process |
        status_history: status_history ++ [status]
      }
    end

    def apply(%ExampleProcessManager.State{status_history: status_history} = process, %ProcessResumed{status: status}) do
      %ExampleProcessManager.State{process |
        status_history: status_history ++ [status]
      }
    end
  end

  test "should resume a process manager with same state when process restarts" do
    process_uuid = UUID.uuid4

    {:ok, process_router} = ProcessRouter.start_link("ExampleProcessManager", ExampleProcessManager, ExampleRouter)

    # transfer funds between account 1 and account 2
    :ok = ExampleRouter.dispatch(%StartProcess{process_uuid: process_uuid, status: "start"})

    assert_receive_event ProcessStarted, fn event ->
      assert event.process_uuid == process_uuid
      assert event.status == "start"
    end

    # wait for process instance to receive event
    Wait.until(fn ->
      %{status_history: ["start"]} = ProcessRouter.process_state(process_router, process_uuid)
    end)

    Helpers.Process.shutdown(process_router)

    {:ok, process_router} = ProcessRouter.start_link("ExampleProcessManager", ExampleProcessManager, ExampleRouter)

    :ok = ExampleRouter.dispatch(%ResumeProcess{process_uuid: process_uuid, status: "resume"})

    wait_for_event(ProcessResumed, fn event -> event.process_uuid == process_uuid end)

    case ProcessRouter.process_state(process_router, process_uuid) do
      {:error, :process_manager_not_found} -> flunk("process state not available")
      state -> assert state.status_history == ["start", "resume"]
    end
  end
end
