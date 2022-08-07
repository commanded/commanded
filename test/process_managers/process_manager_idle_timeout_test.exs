defmodule Commanded.ProcessManagers.ProcessManagerIdleTimeoutTest do
  use ExUnit.Case

  alias Commanded.ProcessManagers.ExampleAggregate.Commands.{Start, Stop}

  alias Commanded.ProcessManagers.{
    ExampleApp,
    ExampleRouter,
    ProcessRouter,
    TimeoutProcessManager
  }

  alias Commanded.Helpers.Wait
  alias Commanded.UUID

  setup do
    start_supervised!(ExampleApp)

    :ok
  end

  describe "process manager idle timeout" do
    test "should shutdown instance after inactivity" do
      {:ok, pm} = TimeoutProcessManager.start_link(idle_timeout: 50)

      aggregate_uuid = UUID.uuid4()
      start = %Start{aggregate_uuid: aggregate_uuid}

      :ok = ExampleRouter.dispatch(start, application: ExampleApp)

      {instance, ref} = wait_for_process_instance(pm, aggregate_uuid)

      assert_receive {:DOWN, ^ref, :process, ^instance, :normal}
    end

    test "should stop instance on demand" do
      {:ok, pm} = TimeoutProcessManager.start_link(idle_timeout: 10_000)

      aggregate_uuid = UUID.uuid4()
      start = %Start{aggregate_uuid: aggregate_uuid}
      stop = %Stop{aggregate_uuid: aggregate_uuid}

      :ok = ExampleRouter.dispatch(start, application: ExampleApp)

      {instance, ref} = wait_for_process_instance(pm, aggregate_uuid)

      :ok = ExampleRouter.dispatch(stop, application: ExampleApp)

      assert_receive {:DOWN, ^ref, :process, ^instance, :normal}
    end
  end

  describe "process manager `:infinity` idle timeout" do
    test "should not shutdown instance" do
      {:ok, pm} = TimeoutProcessManager.start_link(idle_timeout: :infinity)

      aggregate_uuid = UUID.uuid4()
      start = %Start{aggregate_uuid: aggregate_uuid}

      :ok = ExampleRouter.dispatch(start, application: ExampleApp)

      {instance, ref} = wait_for_process_instance(pm, aggregate_uuid)

      refute_receive {:DOWN, ^ref, :process, ^instance, :normal}
    end

    test "should stop instance on demand" do
      {:ok, pm} = TimeoutProcessManager.start_link(idle_timeout: :infinity)

      aggregate_uuid = UUID.uuid4()
      start = %Start{aggregate_uuid: aggregate_uuid}
      stop = %Stop{aggregate_uuid: aggregate_uuid}

      :ok = ExampleRouter.dispatch(start, application: ExampleApp)

      {instance, ref} = wait_for_process_instance(pm, aggregate_uuid)

      :ok = ExampleRouter.dispatch(stop, application: ExampleApp)

      assert_receive {:DOWN, ^ref, :process, ^instance, :normal}
    end
  end

  defp wait_for_process_instance(pm, process_uuid) do
    Wait.until(fn ->
      assert {:ok, instance} = ProcessRouter.process_instance(pm, process_uuid)

      ref = Process.monitor(instance)

      {instance, ref}
    end)
  end
end
