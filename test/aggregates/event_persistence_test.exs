defmodule Commanded.Entities.EventPersistenceTest do
  use Commanded.StorageCase

  import Commanded.Enumerable, only: [pluck: 2]

  alias Commanded.Aggregates.{Aggregate,ExecutionContext}
  alias Commanded.EventStore

  defmodule ExampleAggregate do
    defstruct [
      items: [],
      last_index: 0,
    ]

    defmodule Commands do
      defmodule AppendItems, do: defstruct [count: 0]
    end

    defmodule Events do
      defmodule ItemAppended, do: defstruct [index: nil]
    end

    alias Commands.{AppendItems}
    alias Events.{ItemAppended}

    def append_items(%ExampleAggregate{last_index: last_index}, count) do
      Enum.map(1..count, fn index ->
        %ItemAppended{index: last_index + index}
      end)
    end

    # state mutatators

    def apply(%ExampleAggregate{items: items} = state, %ItemAppended{index: index}) do
      %ExampleAggregate{state |
        items: items ++ [index],
        last_index: index,
      }
    end
  end

  alias ExampleAggregate.Commands.{AppendItems}

  defmodule AppendItemsHandler do
    @behaviour Commanded.Commands.Handler

    def handle(%ExampleAggregate{} = aggregate, %AppendItems{count: count}), do: ExampleAggregate.append_items(aggregate, count)
  end

  test "should persist pending events in order applied" do
    aggregate_uuid = UUID.uuid4

    {:ok, ^aggregate_uuid} = Commanded.Aggregates.Supervisor.open_aggregate(ExampleAggregate, aggregate_uuid)

    {:ok, 10} = Aggregate.execute(ExampleAggregate, aggregate_uuid, %ExecutionContext{command: %AppendItems{count: 10}, handler: AppendItemsHandler, function: :handle})

    recorded_events = EventStore.stream_forward(aggregate_uuid, 0) |> Enum.to_list()

    assert recorded_events |> pluck(:data) |> pluck(:index) == Enum.to_list(1..10)
    assert pluck(recorded_events, :event_number) == Enum.to_list(1..10)

    Enum.each(recorded_events, fn recorded_event ->
      assert recorded_event.stream_id == aggregate_uuid
    end)
  end

  test "should persist event metadata" do
    aggregate_uuid = UUID.uuid4

    {:ok, ^aggregate_uuid} = Commanded.Aggregates.Supervisor.open_aggregate(ExampleAggregate, aggregate_uuid)

    metadata = %{"ip_address" => "127.0.0.1"}
    context = %ExecutionContext{command: %AppendItems{count: 10}, metadata: metadata, handler: AppendItemsHandler, function: :handle}

    {:ok, 10} = Aggregate.execute(ExampleAggregate, aggregate_uuid, context)

    recorded_events = EventStore.stream_forward(aggregate_uuid, 0) |> Enum.to_list()

    Enum.each(recorded_events, fn recorded_event ->
      assert recorded_event.metadata == metadata
    end)
  end

  test "should reload persisted events when restarting aggregate process" do
    aggregate_uuid = UUID.uuid4

    {:ok, ^aggregate_uuid} = Commanded.Aggregates.Supervisor.open_aggregate(ExampleAggregate, aggregate_uuid)

    {:ok, 10} = Aggregate.execute(ExampleAggregate, aggregate_uuid, %ExecutionContext{command: %AppendItems{count: 10}, handler: AppendItemsHandler, function: :handle})

    Commanded.Helpers.Process.shutdown(ExampleAggregate, aggregate_uuid)

    {:ok, ^aggregate_uuid} = Commanded.Aggregates.Supervisor.open_aggregate(ExampleAggregate, aggregate_uuid)

    assert Aggregate.aggregate_version(ExampleAggregate, aggregate_uuid) == 10
    assert Aggregate.aggregate_state(ExampleAggregate, aggregate_uuid) == %Commanded.Entities.EventPersistenceTest.ExampleAggregate{
      items: 1..10 |> Enum.to_list(),
      last_index: 10,
    }
  end

  test "should reload persisted events in batches when restarting aggregate process" do
    aggregate_uuid = UUID.uuid4

    {:ok, ^aggregate_uuid} = Commanded.Aggregates.Supervisor.open_aggregate(ExampleAggregate, aggregate_uuid)

    {:ok, 100} = Aggregate.execute(ExampleAggregate, aggregate_uuid, %ExecutionContext{command: %AppendItems{count: 100}, handler: AppendItemsHandler, function: :handle})
    {:ok, 200} = Aggregate.execute(ExampleAggregate, aggregate_uuid, %ExecutionContext{command: %AppendItems{count: 100}, handler: AppendItemsHandler, function: :handle})
    {:ok, 201} = Aggregate.execute(ExampleAggregate, aggregate_uuid, %ExecutionContext{command: %AppendItems{count: 1}, handler: AppendItemsHandler, function: :handle})

    Commanded.Helpers.Process.shutdown(ExampleAggregate, aggregate_uuid)

    {:ok, ^aggregate_uuid} = Commanded.Aggregates.Supervisor.open_aggregate(ExampleAggregate, aggregate_uuid)

    assert Aggregate.aggregate_version(ExampleAggregate, aggregate_uuid) == 201
    assert Aggregate.aggregate_state(ExampleAggregate, aggregate_uuid) == %Commanded.Entities.EventPersistenceTest.ExampleAggregate{
      items: 1..201 |> Enum.to_list,
      last_index: 201,
    }
  end

  test "should prefix stream UUID with aggregate indentity prefix" do
    aggregate_uuid = UUID.uuid4()
    prefix = "example-preifx-"

    {:ok, ^aggregate_uuid} = Commanded.Aggregates.Supervisor.open_aggregate(ExampleAggregate, aggregate_uuid, prefix)

    context = %ExecutionContext{command: %AppendItems{count: 1}, handler: AppendItemsHandler, function: :handle}

    {:ok, 1} = Aggregate.execute(ExampleAggregate, aggregate_uuid, context)

    recorded_events = EventStore.stream_forward(prefix <> aggregate_uuid, 0) |> Enum.to_list()
    assert length(recorded_events) == 1

    assert {:error, :stream_not_found} == EventStore.stream_forward(aggregate_uuid, 0)
  end
end
