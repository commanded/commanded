defmodule Commanded.ProcessManagers.ProcessManagerAfterCommandTest do
  use ExUnit.Case

  import Commanded.Assertions.EventAssertions
  import Commanded.Enumerable

  alias Commanded.EventStore
  alias Commanded.Helpers.Wait
  alias Commanded.ProcessManagers.AfterCommandProcessManager
  alias Commanded.ProcessManagers.ExampleAggregate.Commands.Publish
  alias Commanded.ProcessManagers.ExampleAggregate.Commands.Start
  alias Commanded.ProcessManagers.ExampleAggregate.Events.Interested
  alias Commanded.ProcessManagers.ExampleAggregate.Events.Started
  alias Commanded.ProcessManagers.ExampleAggregate.Events.Stopped
  alias Commanded.ProcessManagers.ExampleAggregate.Events.Uninterested
  alias Commanded.ProcessManagers.ExampleApp
  alias Commanded.ProcessManagers.ExampleRouter
  alias Commanded.ProcessManagers.ProcessRouter
  alias Commanded.UUID

  setup do
    start_supervised!(ExampleApp)

    :ok
  end

  test "should stop process manager instance after specified command" do
    aggregate_uuid = UUID.uuid4()
    source_uuid = "\"AfterCommandProcessManager\"-\"#{aggregate_uuid}\""

    {:ok, process_router} = AfterCommandProcessManager.start_link()

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

    # Process state snapshot should be created
    assert {:ok, _} = EventStore.read_snapshot(ExampleApp, source_uuid)

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
      assert EventStore.read_snapshot(ExampleApp, source_uuid) == {:error, :snapshot_not_found}
    end)
  end
end
