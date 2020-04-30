defmodule Commanded.ProcessManagers.ProcessRouterProcessPendingEventsTest do
  use ExUnit.Case

  import Commanded.Assertions.EventAssertions
  import Commanded.Enumerable

  alias Commanded.EventStore
  alias Commanded.Helpers.Wait
  alias Commanded.ProcessManagers.ExampleApp
  alias Commanded.ProcessManagers.ExampleRouter
  alias Commanded.ProcessManagers.ExampleProcessManager
  alias Commanded.ProcessManagers.ProcessRouter
  alias Commanded.ProcessManagers.ProcessManagerInstance
  alias Commanded.ProcessManagers.ExampleAggregate.Commands.{Publish, Start}
  alias Commanded.ProcessManagers.ExampleAggregate.Events.Interested
  alias Commanded.ProcessManagers.ExampleAggregate.Events.Started
  alias Commanded.ProcessManagers.ExampleAggregate.Events.Stopped
  alias Commanded.ProcessManagers.ExampleAggregate.Events.Uninterested

  setup do
    start_supervised!(ExampleApp)

    :ok
  end

  test "should start process manager instance and successfully dispatch command" do
    aggregate_uuid = UUID.uuid4()

    {:ok, process_router} = ExampleProcessManager.start_link()

    :ok = ExampleRouter.dispatch(%Start{aggregate_uuid: aggregate_uuid}, application: ExampleApp)

    # Dispatch command to publish multiple events and trigger dispatch of the stop command
    :ok =
      ExampleRouter.dispatch(
        %Publish{
          aggregate_uuid: aggregate_uuid,
          interesting: 10,
          uninteresting: 1
        },
        application: ExampleApp
      )

    assert_receive_event(ExampleApp, Stopped, fn event ->
      assert event.aggregate_uuid == aggregate_uuid
    end)

    events = EventStore.stream_forward(ExampleApp, aggregate_uuid) |> Enum.to_list()

    assert pluck(events, :data) == [
             %Started{aggregate_uuid: aggregate_uuid},
             %Interested{aggregate_uuid: aggregate_uuid, index: 1},
             %Interested{aggregate_uuid: aggregate_uuid, index: 2},
             %Interested{aggregate_uuid: aggregate_uuid, index: 3},
             %Interested{aggregate_uuid: aggregate_uuid, index: 4},
             %Interested{aggregate_uuid: aggregate_uuid, index: 5},
             %Interested{aggregate_uuid: aggregate_uuid, index: 6},
             %Interested{aggregate_uuid: aggregate_uuid, index: 7},
             %Interested{aggregate_uuid: aggregate_uuid, index: 8},
             %Interested{aggregate_uuid: aggregate_uuid, index: 9},
             %Interested{aggregate_uuid: aggregate_uuid, index: 10},
             %Uninterested{aggregate_uuid: aggregate_uuid, index: 1},
             %Stopped{aggregate_uuid: aggregate_uuid}
           ]

    Wait.until(fn ->
      # Process instance should be stopped
      assert ProcessRouter.process_instance(process_router, aggregate_uuid) ==
               {:error, :process_manager_not_found}

      # Process state snapshot should be deleted
      assert EventStore.read_snapshot(ExampleApp, "example_process_manager-#{aggregate_uuid}") ==
               {:error, :snapshot_not_found}
    end)
  end

  test "should ignore uninteresting events" do
    aggregate_uuid = UUID.uuid4()

    {:ok, process_router} = ExampleProcessManager.start_link()

    :ok = ExampleRouter.dispatch(%Start{aggregate_uuid: aggregate_uuid}, application: ExampleApp)

    # Dispatch commands to publish a mix of interesting and uninteresting events for the process router
    :ok =
      ExampleRouter.dispatch(
        %Publish{
          aggregate_uuid: aggregate_uuid,
          interesting: 0,
          uninteresting: 2
        },
        application: ExampleApp
      )

    :ok =
      ExampleRouter.dispatch(
        %Publish{
          aggregate_uuid: aggregate_uuid,
          interesting: 0,
          uninteresting: 2
        },
        application: ExampleApp
      )

    :ok =
      ExampleRouter.dispatch(
        %Publish{
          aggregate_uuid: aggregate_uuid,
          interesting: 10,
          uninteresting: 0
        },
        application: ExampleApp
      )

    assert_receive_event(ExampleApp, Stopped, fn event ->
      assert event.aggregate_uuid == aggregate_uuid
    end)

    events = EventStore.stream_forward(ExampleApp, aggregate_uuid) |> Enum.to_list()

    assert pluck(events, :data) == [
             %Started{aggregate_uuid: aggregate_uuid},
             %Uninterested{aggregate_uuid: aggregate_uuid, index: 1},
             %Uninterested{aggregate_uuid: aggregate_uuid, index: 2},
             %Uninterested{aggregate_uuid: aggregate_uuid, index: 1},
             %Uninterested{aggregate_uuid: aggregate_uuid, index: 2},
             %Interested{aggregate_uuid: aggregate_uuid, index: 1},
             %Interested{aggregate_uuid: aggregate_uuid, index: 2},
             %Interested{aggregate_uuid: aggregate_uuid, index: 3},
             %Interested{aggregate_uuid: aggregate_uuid, index: 4},
             %Interested{aggregate_uuid: aggregate_uuid, index: 5},
             %Interested{aggregate_uuid: aggregate_uuid, index: 6},
             %Interested{aggregate_uuid: aggregate_uuid, index: 7},
             %Interested{aggregate_uuid: aggregate_uuid, index: 8},
             %Interested{aggregate_uuid: aggregate_uuid, index: 9},
             %Interested{aggregate_uuid: aggregate_uuid, index: 10},
             %Stopped{aggregate_uuid: aggregate_uuid}
           ]

    Wait.until(fn ->
      # Process instance should be stopped
      assert ProcessRouter.process_instance(process_router, aggregate_uuid) ==
               {:error, :process_manager_not_found}
    end)
  end

  test "should ignore past events when starting subscription from current" do
    aggregate_uuid = UUID.uuid4()

    :ok = ExampleRouter.dispatch(%Start{aggregate_uuid: aggregate_uuid}, application: ExampleApp)

    :ok =
      ExampleRouter.dispatch(
        %Publish{
          aggregate_uuid: aggregate_uuid,
          interesting: 4,
          uninteresting: 0
        },
        application: ExampleApp
      )

    wait_for_event(ExampleApp, Interested, fn event -> event.index == 4 end)

    {:ok, process_router} = ExampleProcessManager.start_link(start_from: :current)

    assert ProcessRouter.process_instances(process_router) == []

    :ok = ExampleRouter.dispatch(%Start{aggregate_uuid: aggregate_uuid}, application: ExampleApp)

    :ok =
      ExampleRouter.dispatch(
        %Publish{
          aggregate_uuid: aggregate_uuid,
          interesting: 6,
          uninteresting: 0
        },
        application: ExampleApp
      )

    wait_for_event(ExampleApp, Interested, fn event -> event.index == 6 end)

    Wait.until(fn ->
      assert {:ok, process_instance} =
               ProcessRouter.process_instance(process_router, aggregate_uuid)

      %{items: items} = ProcessManagerInstance.process_state(process_instance)

      assert items == [1, 2, 3, 4, 5, 6]
    end)
  end
end
