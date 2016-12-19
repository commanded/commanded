defmodule Commanded.ProcessManager.ProcessRouterProcessPendingEventsTest do
  use Commanded.StorageCase

  alias Commanded.ProcessManagers.ProcessRouter

  import Commanded.Assertions.EventAssertions
  import Commanded.Enumerable

  defmodule ExampleAggregate do
    defstruct [
      uuid: nil,
      state: nil,
      items: [],
    ]

    defmodule Commands do
      defmodule Start, do: defstruct [:aggregate_uuid]
      defmodule Publish, do: defstruct [:aggregate_uuid, :interesting, :uninteresting]
      defmodule Stop, do: defstruct [:aggregate_uuid]
    end

    defmodule Events do
      defmodule Started, do: defstruct [:aggregate_uuid]
      defmodule Interested, do: defstruct [:aggregate_uuid, :index]
      defmodule Uninterested, do: defstruct [:aggregate_uuid, :index]
      defmodule Stopped, do: defstruct [:aggregate_uuid]
    end

    def start(%ExampleAggregate{}, aggregate_uuid) do
      %Events.Started{aggregate_uuid: aggregate_uuid}
    end

    def publish(%ExampleAggregate{uuid: aggregate_uuid}, interesting, uninteresting) do
      Enum.concat(
        publish_interesting(aggregate_uuid, interesting, 1),
        publish_uninteresting(aggregate_uuid, uninteresting, 1)
      )
    end

    def stop(%ExampleAggregate{uuid: aggregate_uuid}) do
      %Events.Stopped{aggregate_uuid: aggregate_uuid}
    end

    defp publish_interesting(_aggregate_uuid, 0, _index), do: []
    defp publish_interesting(aggregate_uuid, interesting, index) do
      [
        %Events.Interested{aggregate_uuid: aggregate_uuid, index: index},
      ] ++ publish_interesting(aggregate_uuid, interesting - 1, index + 1)
    end

    defp publish_uninteresting(_aggregate_uuid, 0, _index), do: []
    defp publish_uninteresting(aggregate_uuid, interesting, index) do
      [
        %Events.Uninterested{aggregate_uuid: aggregate_uuid, index: index},
      ] ++ publish_uninteresting(aggregate_uuid, interesting - 1, index + 1)
    end

    # state mutatators

    def apply(%ExampleAggregate{} = state, %Events.Started{aggregate_uuid: aggregate_uuid}), do: %ExampleAggregate{state | uuid: aggregate_uuid, state: :started}
    def apply(%ExampleAggregate{items: items} = state, %Events.Interested{index: index}), do: %ExampleAggregate{state | items: items ++ [index]}
    def apply(%ExampleAggregate{} = state, %Events.Uninterested{}), do: state
    def apply(%ExampleAggregate{} = state, %Events.Stopped{}), do: %ExampleAggregate{state | state: :stopped}
  end

  alias ExampleAggregate.Commands.{Start,Publish,Stop}
  alias ExampleAggregate.Events.{Started,Interested,Uninterested,Stopped}

  defmodule ExampleCommandHandler do
    @behaviour Commanded.Commands.Handler

    def handle(%ExampleAggregate{} = aggregate, %Start{aggregate_uuid: aggregate_uuid}), do: ExampleAggregate.start(aggregate, aggregate_uuid)
    def handle(%ExampleAggregate{} = aggregate, %Publish{interesting: interesting, uninteresting: uninteresting}), do: ExampleAggregate.publish(aggregate, interesting, uninteresting)
    def handle(%ExampleAggregate{} = aggregate, %Stop{}), do: ExampleAggregate.stop(aggregate)
  end

  defmodule ExampleProcessManager do
    @behaviour Commanded.ProcessManagers.ProcessManager

    defstruct [
      status: nil,
      items: [],
    ]

    def interested?(%Started{aggregate_uuid: aggregate_uuid}), do: {:start, aggregate_uuid}
    def interested?(%Interested{aggregate_uuid: aggregate_uuid}), do: {:continue, aggregate_uuid}
    def interested?(%Stopped{aggregate_uuid: aggregate_uuid}), do: {:continue, aggregate_uuid}
    def interested?(_event), do: false

    def handle(%ExampleProcessManager{}, %Interested{index: 10, aggregate_uuid: aggregate_uuid}) do
      %Stop{aggregate_uuid: aggregate_uuid}
    end

    # ignore other events
    def handle(_process_manager, _event), do: []

    ## state mutators

    def apply(%ExampleProcessManager{} = process_manager, %Started{}) do
      %ExampleProcessManager{process_manager |
        status: :started
      }
    end

    def apply(%ExampleProcessManager{items: items} = process_manager, %Interested{index: index}) do
      %ExampleProcessManager{process_manager |
        items: items ++ [index]
      }
    end

    def apply(%ExampleProcessManager{} = process_manager, %Stopped{}) do
      %ExampleProcessManager{process_manager |
        status: :stopped
      }
    end
  end

  defmodule Router do
    use Commanded.Commands.Router

    dispatch [Start,Publish,Stop], to: ExampleCommandHandler, aggregate: ExampleAggregate, identity: :aggregate_uuid
  end

  test "should start process manager instance and successfully dispatch command" do
    aggregate_uuid = UUID.uuid4

    {:ok, process_router} = ProcessRouter.start_link("example_process_manager", ExampleProcessManager, Router)

    :ok = Router.dispatch(%Start{aggregate_uuid: aggregate_uuid})

    # dispatch command to publish multiple events and trigger dispatch of the stop command
    :ok = Router.dispatch(%Publish{aggregate_uuid: aggregate_uuid, interesting: 10, uninteresting: 1})

    assert_receive_event Stopped, fn event ->
      assert event.aggregate_uuid == aggregate_uuid
    end

    {:ok, events} = EventStore.read_all_streams_forward

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

    :timer.sleep 100

    %{items: items} = ProcessRouter.process_state(process_router, aggregate_uuid)
    assert items == [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
  end

  test "should ignore uninteresting events" do
    aggregate_uuid = UUID.uuid4

    {:ok, _} = ProcessRouter.start_link("example_process_manager", ExampleProcessManager, Router)

    :ok = Router.dispatch(%Start{aggregate_uuid: aggregate_uuid})

    # dispatch commands to publish a mix of interesting and uninteresting events for the process router
    :ok = Router.dispatch(%Publish{aggregate_uuid: aggregate_uuid, interesting: 0, uninteresting: 2})
    :ok = Router.dispatch(%Publish{aggregate_uuid: aggregate_uuid, interesting: 0, uninteresting: 2})
    :ok = Router.dispatch(%Publish{aggregate_uuid: aggregate_uuid, interesting: 10, uninteresting: 0})

    assert_receive_event Stopped, fn event ->
      assert event.aggregate_uuid == aggregate_uuid
    end

    {:ok, events} = EventStore.read_all_streams_forward

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
  end

  test "should ignore past events when starting subscription from current" do
    aggregate_uuid = UUID.uuid4

    :ok = Router.dispatch(%Start{aggregate_uuid: aggregate_uuid})
    :ok = Router.dispatch(%Publish{aggregate_uuid: aggregate_uuid, interesting: 4, uninteresting: 0})

    wait_for_event Interested, fn event -> event.index == 4 end

    {:ok, process_router} = ProcessRouter.start_link("example_process_manager", ExampleProcessManager, Router, start_from: :current)

    :ok = Router.dispatch(%Start{aggregate_uuid: aggregate_uuid})
    :ok = Router.dispatch(%Publish{aggregate_uuid: aggregate_uuid, interesting: 6, uninteresting: 0})

    wait_for_event Interested, fn event -> event.index == 6 end
    :timer.sleep 100

    %{items: items} = ProcessRouter.process_state(process_router, aggregate_uuid)
    assert items == [1, 2, 3, 4, 5, 6]
  end
end
