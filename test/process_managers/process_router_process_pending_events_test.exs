defmodule Commanded.ProcessManagers.ProcessRouterProcessPendingEventsTest do
  use Commanded.StorageCase

  import Commanded.Assertions.EventAssertions
  import Commanded.Enumerable

  alias Commanded.EventStore
  alias Commanded.Helpers.Wait
  alias Commanded.ProcessManagers.{ExampleRouter,ExampleProcessManager,ProcessRouter,ProcessManagerInstance}
  alias Commanded.ProcessManagers.ExampleAggregate.Commands.{Publish,Start}
  alias Commanded.ProcessManagers.ExampleAggregate.Events.{Interested,Started,Stopped,Uninterested}

  test "should start process manager instance and successfully dispatch command" do
    aggregate_uuid = UUID.uuid4

    {:ok, process_router} = ExampleProcessManager.start_link()

    :ok = ExampleRouter.dispatch(%Start{aggregate_uuid: aggregate_uuid})

    # dispatch command to publish multiple events and trigger dispatch of the stop command
    :ok = ExampleRouter.dispatch(%Publish{aggregate_uuid: aggregate_uuid, interesting: 10, uninteresting: 1})

    assert_receive_event Stopped, fn event ->
      assert event.aggregate_uuid == aggregate_uuid
    end

    events = EventStore.stream_forward(aggregate_uuid) |> Enum.to_list()

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
      %Stopped{aggregate_uuid: aggregate_uuid},
    ]

    Wait.until fn ->
      # process instance should be stopped
      assert ProcessRouter.process_instance(process_router, aggregate_uuid) == {:error, :process_manager_not_found}

      # process state snapshot should be deleted
      assert EventStore.read_snapshot("example_process_manager-#{aggregate_uuid}") == {:error, :snapshot_not_found}
    end
  end

  test "should ignore uninteresting events" do
    aggregate_uuid = UUID.uuid4

    {:ok, process_router} = ExampleProcessManager.start_link()

    :ok = ExampleRouter.dispatch(%Start{aggregate_uuid: aggregate_uuid})

    # dispatch commands to publish a mix of interesting and uninteresting events for the process router
    :ok = ExampleRouter.dispatch(%Publish{aggregate_uuid: aggregate_uuid, interesting: 0, uninteresting: 2})
    :ok = ExampleRouter.dispatch(%Publish{aggregate_uuid: aggregate_uuid, interesting: 0, uninteresting: 2})
    :ok = ExampleRouter.dispatch(%Publish{aggregate_uuid: aggregate_uuid, interesting: 10, uninteresting: 0})

    assert_receive_event Stopped, fn event ->
      assert event.aggregate_uuid == aggregate_uuid
    end

    events =
      aggregate_uuid
      |> EventStore.stream_forward()
      |> Enum.to_list()

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
      %Stopped{aggregate_uuid: aggregate_uuid},
    ]

    Wait.until fn ->
      # process instance should be stopped
      assert ProcessRouter.process_instance(process_router, aggregate_uuid) == {:error, :process_manager_not_found}
    end
  end

  test "should ignore past events when starting subscription from current" do
    aggregate_uuid = UUID.uuid4

    :ok = ExampleRouter.dispatch(%Start{aggregate_uuid: aggregate_uuid})
    :ok = ExampleRouter.dispatch(%Publish{aggregate_uuid: aggregate_uuid, interesting: 4, uninteresting: 0})

    wait_for_event Interested, fn event -> event.index == 4 end

    {:ok, process_router} = ExampleProcessManager.start_link(start_from: :current)

    :ok = ExampleRouter.dispatch(%Start{aggregate_uuid: aggregate_uuid})
    :ok = ExampleRouter.dispatch(%Publish{aggregate_uuid: aggregate_uuid, interesting: 6, uninteresting: 0})

    wait_for_event Interested, fn event -> event.index == 6 end
    :timer.sleep 100

    process_instance = ProcessRouter.process_instance(process_router, aggregate_uuid)
    %{items: items} = ProcessManagerInstance.process_state(process_instance)
    assert items == [1, 2, 3, 4, 5, 6]
  end

  test "should stop process router when handling event errors" do
    aggregate_uuid = UUID.uuid4

    {:ok, process_router} = ExampleProcessManager.start_link()

    Process.unlink(process_router)
    ref = Process.monitor(process_router)

    :ok = Router.dispatch(%Start{aggregate_uuid: aggregate_uuid})
    :ok = Router.dispatch(%Error{aggregate_uuid: aggregate_uuid})

    # should shutdown process
    assert_receive {:DOWN, ^ref, _, _, _}
  end
end
