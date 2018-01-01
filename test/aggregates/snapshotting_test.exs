defmodule Commanded.Aggregates.SnapshottingTest do
  use Commanded.StorageCase

  alias Commanded.Aggregates.{
    Aggregate,
    AppendItemsHandler,
    ExampleAggregate,
    ExecutionContext,
  }
  alias Commanded.Aggregates.ExampleAggregate.Commands.AppendItems
  alias Commanded.EventStore
  alias Commanded.EventStore.SnapshotData

  test "should not shapshot when not configured" do
    aggregate_uuid = UUID.uuid4()
    append_items(aggregate_uuid, 1, snapshot_every: nil)

    assert EventStore.read_snapshot(aggregate_uuid) == {:error, :snapshot_not_found}
  end

  test "should not shapshot when set to 0" do
    aggregate_uuid = UUID.uuid4()
    append_items(aggregate_uuid, 1, snapshot_every: 0)

    assert EventStore.read_snapshot(aggregate_uuid) == {:error, :snapshot_not_found}
  end


  test "should not shapshot when fewer snapshot interval" do
    aggregate_uuid = UUID.uuid4()
    append_items(aggregate_uuid, 9, snapshot_every: 10)

    assert EventStore.read_snapshot(aggregate_uuid) == {:error, :snapshot_not_found}
  end

  test "should shapshot when exactly snapshot interval" do
    aggregate_uuid = UUID.uuid4()
    append_items(aggregate_uuid, 10, snapshot_every: 10)

    assert {:ok, snapshot} = EventStore.read_snapshot(aggregate_uuid)
    assert snapshot == %SnapshotData{
      source_uuid: aggregate_uuid,
      source_version: 10,
      source_type: "Elixir.Commanded.Aggregates.ExampleAggregate",
      data: %ExampleAggregate{
        items: Enum.to_list(1..10),
        last_index: 10,
      },
      metadata: nil,
      created_at: nil,
    }
  end

  test "should shapshot when more than snapshot interval" do
    aggregate_uuid = UUID.uuid4()
    append_items(aggregate_uuid, 11, snapshot_every: 10)

    assert {:ok, snapshot} = EventStore.read_snapshot(aggregate_uuid)
    assert snapshot == %SnapshotData{
      source_uuid: aggregate_uuid,
      source_version: 11,
      source_type: "Elixir.Commanded.Aggregates.ExampleAggregate",
      data: %ExampleAggregate{
        items: Enum.to_list(1..11),
        last_index: 11,
      },
      metadata: nil,
      created_at: nil,
    }
  end

  test "should shapshot again when interval reached" do
    aggregate_uuid = UUID.uuid4()

    append_items(aggregate_uuid, 10, snapshot_every: 10)
    assert {:ok, snapshot} = EventStore.read_snapshot(aggregate_uuid)
    assert snapshot.source_version == 10

    append_items(aggregate_uuid, 1, snapshot_every: 10)
    assert {:ok, snapshot} = EventStore.read_snapshot(aggregate_uuid)
    assert snapshot.source_version == 10

    append_items(aggregate_uuid, 10, snapshot_every: 10)

    assert {:ok, snapshot} = EventStore.read_snapshot(aggregate_uuid)
    assert snapshot == %SnapshotData{
      source_uuid: aggregate_uuid,
      source_version: 21,
      source_type: "Elixir.Commanded.Aggregates.ExampleAggregate",
      data: %ExampleAggregate{
        items: Enum.to_list(1..21),
        last_index: 21,
      },
      metadata: nil,
      created_at: nil,
    }
  end

  defp append_items(aggregate_uuid, count, snapshot_every: snapshot_every) do
    execution_context = %ExecutionContext{
      command: %AppendItems{count: count},
      handler: AppendItemsHandler,
      function: :handle,
      snapshot_every: snapshot_every,
    }

    {:ok, ^aggregate_uuid} = Commanded.Aggregates.Supervisor.open_aggregate(ExampleAggregate, aggregate_uuid)
    {:ok, _count, _events} = Aggregate.execute(ExampleAggregate, aggregate_uuid, execution_context)
  end
end
