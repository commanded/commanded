defmodule Commanded.Entities.EventPersistenceTest do
  use Commanded.StorageCase

  import Commanded.Enumerable, only: [pluck: 2]

  alias Commanded.Aggregates.{Registry,Aggregate}

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

    def handle(%ExampleAggregate{} = aggregate, %AppendItems{count: count}) do
      aggregate
      |> ExampleAggregate.append_items(count)
    end
  end

  test "should persist pending events in order applied" do
    aggregate_uuid = UUID.uuid4

    {:ok, aggregate} = Registry.open_aggregate(ExampleAggregate, aggregate_uuid)

    :ok = Aggregate.execute(aggregate, %AppendItems{count: 10}, AppendItemsHandler)

    {:ok, recorded_events} = EventStore.read_stream_forward(aggregate_uuid, 0)

    assert recorded_events |> pluck(:data) |> pluck(:index) == Enum.to_list(1..10)
  end

  test "should reload persisted events when restarting aggregate process" do
    aggregate_uuid = UUID.uuid4

    {:ok, aggregate} = Registry.open_aggregate(ExampleAggregate, aggregate_uuid)

    :ok = Aggregate.execute(aggregate, %AppendItems{count: 10}, AppendItemsHandler)

    Commanded.Helpers.Process.shutdown(aggregate)

    {:ok, aggregate} = Registry.open_aggregate(ExampleAggregate, aggregate_uuid)
    aggregate_state = Aggregate.aggregate_state(aggregate)

    # assert aggregate_state.uuid == aggregate_uuid
    # assert aggregate_state.version == 10
    # assert aggregate_state.pending_events == []
    assert aggregate_state == %Commanded.Entities.EventPersistenceTest.ExampleAggregate{
      items: 1..10 |> Enum.to_list,
      last_index: 10,
    }
  end

  test "should reload persisted events in batches when restarting aggregate process" do
    aggregate_uuid = UUID.uuid4

    {:ok, aggregate} = Registry.open_aggregate(ExampleAggregate, aggregate_uuid)

    :ok = Aggregate.execute(aggregate, %AppendItems{count: 100}, AppendItemsHandler)
    :ok = Aggregate.execute(aggregate, %AppendItems{count: 100}, AppendItemsHandler)
    :ok = Aggregate.execute(aggregate, %AppendItems{count: 1}, AppendItemsHandler)

    Commanded.Helpers.Process.shutdown(aggregate)

    {:ok, aggregate} = Registry.open_aggregate(ExampleAggregate, aggregate_uuid)

    aggregate_state = Aggregate.aggregate_state(aggregate)

    # assert aggregate_state.uuid == aggregate_uuid
    # assert aggregate_state.version == 201
    # assert aggregate_state.pending_events == []
    assert aggregate_state == %Commanded.Entities.EventPersistenceTest.ExampleAggregate{
      items: 1..201 |> Enum.to_list,
      last_index: 201,
    }
  end
end
