defmodule Commanded.ProcessManagers.ResumeProcessManagerTest do
  use Commanded.StorageCase

  import Commanded.Assertions.EventAssertions

  alias Commanded.Helpers.{ProcessHelper,Wait}
  alias Commanded.ProcessManagers.{ProcessRouter,ProcessManagerInstance}
  alias Commanded.ProcessManagers.{ResumeRouter,ResumeProcessManager}
  alias Commanded.ProcessManagers.ResumeAggregate.Commands.{StartProcess,ResumeProcess}
  alias Commanded.ProcessManagers.ResumeAggregate.Events.{ProcessStarted,ProcessResumed}

  test "should resume a process manager with same state when process restarts" do
    process_uuid = UUID.uuid4

    {:ok, process_router} = ResumeProcessManager.start_link()

    :ok = ResumeRouter.dispatch(%StartProcess{process_uuid: process_uuid, status: "start"})

    assert_receive_event ProcessStarted, fn event ->
      assert event.process_uuid == process_uuid
      assert event.status == "start"
    end

    # wait for process instance to receive event
    Wait.until(fn ->
      process_instance = ProcessRouter.process_instance(process_router, process_uuid)

      assert process_instance != {:error, :process_manager_not_found}
      assert %{status_history: ["start"]} = ProcessManagerInstance.process_state(process_instance)
    end)

    ProcessHelper.shutdown(process_router)

    # wait for subscription to receive DOWN notification and remove subscription's PID
    :timer.sleep(1_000)

    {:ok, process_router} = ResumeProcessManager.start_link()

    :ok = ResumeRouter.dispatch(%ResumeProcess{process_uuid: process_uuid, status: "resume"})

    wait_for_event(ProcessResumed, fn event -> event.process_uuid == process_uuid end)

    Wait.until(fn ->
      process_instance = ProcessRouter.process_instance(process_router, process_uuid)
      assert process_instance != {:error, :process_manager_not_found}

      state = ProcessManagerInstance.process_state(process_instance)
      assert state.status_history == ["start", "resume"]
    end)
  end
end
