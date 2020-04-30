defmodule Commanded.Aggregates.EventPersistenceTest do
  use ExUnit.Case

  import Commanded.Enumerable, only: [pluck: 2]

  alias Commanded.Aggregates.{Aggregate, AppendItemsHandler, ExampleAggregate}
  alias Commanded.Aggregates.ExampleAggregate.Commands.{AppendItems, NoOp}
  alias Commanded.DefaultApp
  alias Commanded.EventStore
  alias Commanded.Helpers.ProcessHelper
  alias Commanded.Aggregates.ExecutionContext

  setup do
    start_supervised!(DefaultApp)
    :ok
  end

  test "should persist pending events in order applied" do
    aggregate_uuid = UUID.uuid4()

    {:ok, ^aggregate_uuid} =
      Commanded.Aggregates.Supervisor.open_aggregate(DefaultApp, ExampleAggregate, aggregate_uuid)

    {:ok, 10, events} =
      Aggregate.execute(DefaultApp, ExampleAggregate, aggregate_uuid, %ExecutionContext{
        command: %AppendItems{count: 10},
        handler: AppendItemsHandler,
        function: :handle
      })

    assert length(events) == 10

    recorded_events = EventStore.stream_forward(DefaultApp, aggregate_uuid, 0) |> Enum.to_list()

    assert recorded_events |> pluck(:data) |> pluck(:index) == Enum.to_list(1..10)
    assert pluck(recorded_events, :event_number) == Enum.to_list(1..10)

    Enum.each(recorded_events, fn recorded_event ->
      assert recorded_event.stream_id == aggregate_uuid
    end)
  end

  test "should not persist events when command returns no events" do
    aggregate_uuid = UUID.uuid4()

    {:ok, ^aggregate_uuid} =
      Commanded.Aggregates.Supervisor.open_aggregate(DefaultApp, ExampleAggregate, aggregate_uuid)

    {:ok, 1, events} =
      Aggregate.execute(DefaultApp, ExampleAggregate, aggregate_uuid, %ExecutionContext{
        command: %AppendItems{count: 1},
        handler: AppendItemsHandler,
        function: :handle
      })

    assert length(events) == 1

    {:ok, 1, events} =
      Aggregate.execute(DefaultApp, ExampleAggregate, aggregate_uuid, %ExecutionContext{
        command: %NoOp{},
        handler: ExampleAggregate,
        function: :noop
      })

    assert length(events) == 0

    recorded_events = EventStore.stream_forward(DefaultApp, aggregate_uuid, 0) |> Enum.to_list()
    assert length(recorded_events) == 1
  end

  test "should persist event metadata" do
    aggregate_uuid = UUID.uuid4()

    {:ok, ^aggregate_uuid} =
      Commanded.Aggregates.Supervisor.open_aggregate(DefaultApp, ExampleAggregate, aggregate_uuid)

    metadata = %{"ip_address" => "127.0.0.1"}

    context = %ExecutionContext{
      command: %AppendItems{count: 10},
      metadata: metadata,
      handler: AppendItemsHandler,
      function: :handle
    }

    {:ok, 10, events} = Aggregate.execute(DefaultApp, ExampleAggregate, aggregate_uuid, context)
    assert length(events) == 10

    recorded_events = EventStore.stream_forward(DefaultApp, aggregate_uuid, 0) |> Enum.to_list()

    Enum.each(recorded_events, fn recorded_event ->
      assert recorded_event.metadata == metadata
    end)
  end

  test "should reload persisted events when restarting aggregate process" do
    aggregate_uuid = UUID.uuid4()

    {:ok, ^aggregate_uuid} =
      Commanded.Aggregates.Supervisor.open_aggregate(DefaultApp, ExampleAggregate, aggregate_uuid)

    {:ok, 10, events} =
      Aggregate.execute(DefaultApp, ExampleAggregate, aggregate_uuid, %ExecutionContext{
        command: %AppendItems{count: 10},
        handler: AppendItemsHandler,
        function: :handle
      })

    assert length(events) == 10

    ProcessHelper.shutdown_aggregate(DefaultApp, ExampleAggregate, aggregate_uuid)

    {:ok, ^aggregate_uuid} =
      Commanded.Aggregates.Supervisor.open_aggregate(DefaultApp, ExampleAggregate, aggregate_uuid)

    assert Aggregate.aggregate_version(DefaultApp, ExampleAggregate, aggregate_uuid) == 10

    assert Aggregate.aggregate_state(DefaultApp, ExampleAggregate, aggregate_uuid) ==
             %ExampleAggregate{
               items: 1..10 |> Enum.to_list(),
               last_index: 10
             }
  end

  test "should reload persisted events in batches when restarting aggregate process" do
    aggregate_uuid = UUID.uuid4()

    {:ok, ^aggregate_uuid} =
      Commanded.Aggregates.Supervisor.open_aggregate(DefaultApp, ExampleAggregate, aggregate_uuid)

    {:ok, 100, _events} =
      Aggregate.execute(DefaultApp, ExampleAggregate, aggregate_uuid, %ExecutionContext{
        command: %AppendItems{count: 100},
        handler: AppendItemsHandler,
        function: :handle
      })

    {:ok, 200, _events} =
      Aggregate.execute(DefaultApp, ExampleAggregate, aggregate_uuid, %ExecutionContext{
        command: %AppendItems{count: 100},
        handler: AppendItemsHandler,
        function: :handle
      })

    {:ok, 201, _events} =
      Aggregate.execute(DefaultApp, ExampleAggregate, aggregate_uuid, %ExecutionContext{
        command: %AppendItems{count: 1},
        handler: AppendItemsHandler,
        function: :handle
      })

    ProcessHelper.shutdown_aggregate(DefaultApp, ExampleAggregate, aggregate_uuid)

    {:ok, ^aggregate_uuid} =
      Commanded.Aggregates.Supervisor.open_aggregate(DefaultApp, ExampleAggregate, aggregate_uuid)

    assert Aggregate.aggregate_version(DefaultApp, ExampleAggregate, aggregate_uuid) == 201

    assert Aggregate.aggregate_state(DefaultApp, ExampleAggregate, aggregate_uuid) ==
             %ExampleAggregate{
               items: 1..201 |> Enum.to_list(),
               last_index: 201
             }
  end

  test "should prefix stream UUID with aggregate identity prefix" do
    aggregate_uuid = UUID.uuid4()
    prefix = "example-prefix-"
    prefixed_aggregate_uuid = prefix <> aggregate_uuid

    {:ok, ^prefixed_aggregate_uuid} =
      Commanded.Aggregates.Supervisor.open_aggregate(
        DefaultApp,
        ExampleAggregate,
        prefixed_aggregate_uuid
      )

    context = %ExecutionContext{
      command: %AppendItems{count: 1},
      handler: AppendItemsHandler,
      function: :handle
    }

    {:ok, 1, events} =
      Aggregate.execute(DefaultApp, ExampleAggregate, prefixed_aggregate_uuid, context)

    assert length(events) == 1

    recorded_events =
      EventStore.stream_forward(DefaultApp, prefixed_aggregate_uuid, 0) |> Enum.to_list()

    assert length(recorded_events) == 1

    assert {:error, :stream_not_found} == EventStore.stream_forward(DefaultApp, aggregate_uuid, 0)
  end
end
