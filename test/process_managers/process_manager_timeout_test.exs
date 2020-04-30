defmodule Commanded.ProcessManagers.ProcessManagerTimeoutTest do
  use ExUnit.Case

  alias Commanded.Helpers.Wait
  alias Commanded.ProcessManagers.ProcessRouter
  alias Commanded.ProcessManagers.ExampleAggregate.Commands.Pause
  alias Commanded.ProcessManagers.ExampleAggregate.Commands.Start
  alias Commanded.ProcessManagers.ExampleApp
  alias Commanded.ProcessManagers.ExampleProcessManager
  alias Commanded.ProcessManagers.ExampleRouter

  setup do
    start_supervised!(ExampleApp)

    :ok
  end

  test "should not timeout and shutdown process manager by default" do
    aggregate_uuid = UUID.uuid4()

    {:ok, process_router} = ExampleProcessManager.start_link()
    router_ref = Process.monitor(process_router)

    :ok = ExampleRouter.dispatch(%Start{aggregate_uuid: aggregate_uuid}, application: ExampleApp)

    process_instance = wait_for_process_instance(process_router, aggregate_uuid)
    instance_ref = Process.monitor(process_instance)

    :ok = ExampleRouter.dispatch(%Pause{aggregate_uuid: aggregate_uuid}, application: ExampleApp)

    # Should not shutdown process manager or instance
    refute_receive {:DOWN, ^router_ref, _, _, _}
    refute_receive {:DOWN, ^instance_ref, _, _, _}
  end

  test "should timeout and shutdown process manager when `event_timeout` configured" do
    aggregate_uuid = UUID.uuid4()

    {:ok, process_router} = ExampleProcessManager.start_link(event_timeout: 100)

    router_ref = Process.monitor(process_router)
    Process.unlink(process_router)

    :ok = ExampleRouter.dispatch(%Start{aggregate_uuid: aggregate_uuid}, application: ExampleApp)

    process_instance = wait_for_process_instance(process_router, aggregate_uuid)
    instance_ref = Process.monitor(process_instance)

    :ok = ExampleRouter.dispatch(%Pause{aggregate_uuid: aggregate_uuid}, application: ExampleApp)

    # Should shutdown process manager and instance
    assert_receive {:DOWN, ^router_ref, _, _, :event_timeout}
    assert_receive {:DOWN, ^instance_ref, _, _, :shutdown}
  end

  defp wait_for_process_instance(process_router, aggregate_uuid) do
    Wait.until(fn ->
      assert {:ok, instance} = ProcessRouter.process_instance(process_router, aggregate_uuid)

      instance
    end)
  end
end
