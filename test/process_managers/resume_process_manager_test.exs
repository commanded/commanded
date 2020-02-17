defmodule Commanded.ProcessManagers.ResumeProcessManagerTest do
  use ExUnit.Case

  import Commanded.Assertions.EventAssertions

  alias Commanded.Helpers.{ProcessHelper, Wait}
  alias Commanded.ProcessManagers.ResumeApp
  alias Commanded.ProcessManagers.{ProcessRouter, ProcessManagerInstance}
  alias Commanded.ProcessManagers.{ResumeRouter, ResumeProcessManager}
  alias Commanded.ProcessManagers.ResumeAggregate.Commands.{StartProcess, ResumeProcess}
  alias Commanded.ProcessManagers.ResumeAggregate.Events.{ProcessStarted, ProcessResumed}

  setup do
    start_supervised!(ResumeApp)

    :ok
  end

  test "should resume a process manager with same state when process restarts" do
    {:ok, process_router} = ResumeProcessManager.start_link()

    process_uuid = UUID.uuid4()
    command = %StartProcess{process_uuid: process_uuid, status: "start"}

    :ok = ResumeRouter.dispatch(command, application: ResumeApp)

    assert_receive_event(ResumeApp, ProcessStarted, fn event ->
      assert event.process_uuid == process_uuid
      assert event.status == "start"
    end)

    # wait for process instance to receive event
    Wait.until(fn ->
      assert {:ok, process_instance} =
               ProcessRouter.process_instance(process_router, process_uuid)

      assert %{status_history: ["start"]} = ProcessManagerInstance.process_state(process_instance)
    end)

    ProcessHelper.shutdown(process_router)

    # wait for subscription to receive DOWN notification and remove subscription's PID
    :timer.sleep(1_000)

    {:ok, process_router} = ResumeProcessManager.start_link()

    command = %ResumeProcess{process_uuid: process_uuid, status: "resume"}

    :ok = ResumeRouter.dispatch(command, application: ResumeApp)

    wait_for_event(ResumeApp, ProcessResumed, fn event -> event.process_uuid == process_uuid end)

    Wait.until(fn ->
      assert {:ok, process_instance} =
               ProcessRouter.process_instance(process_router, process_uuid)

      state = ProcessManagerInstance.process_state(process_instance)
      assert state.status_history == ["start", "resume"]
    end)
  end
end
