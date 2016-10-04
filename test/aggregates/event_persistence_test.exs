defmodule Commanded.Entities.EventPersistenceTest do
  use Commanded.StorageCase

  alias Commanded.Aggregates.{Registry,Aggregate}

  defmodule ExampleAggregate do
    use EventSourced.AggregateRoot, fields: [items: []]

    defmodule Commands do
      defmodule AppendItems do
        defstruct count: 0
      end
    end

    defmodule Events do
      defmodule ItemAppended do
        defstruct index: nil
      end
    end

    alias Commands.{AppendItems}
    alias Events.{ItemAppended}

    def append_items(%ExampleAggregate{} = aggregate, count) do
      range = 0..count

      aggregate = Enum.reduce(range, aggregate, fn (index, aggregate) ->
        update(aggregate, %ItemAppended{index: index})
      end)

      {:ok, aggregate}
    end

    # state mutatators

    def apply(%ExampleAggregate.State{items: items} = state, %ItemAppended{index: index}) do
      %ExampleAggregate.State{state |
        items: items ++ [index]
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

    assert recorded_events |> pluck(:data) |> pluck(:index) == Enum.to_list(0..10)
  end

  defp pluck(enumerable, field) do
    Enum.map(enumerable, &Map.get(&1, field))
  end
end
