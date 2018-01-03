defmodule Commanded.Aggregates.SnapshottingTest do
  use Commanded.StorageCase

  alias Commanded.Aggregates.{
    Aggregate,
    AppendItemsHandler,
    ExampleAggregate,
    ExecutionContext
  }

  alias Commanded.Aggregates.ExampleAggregate.Commands.AppendItems
  alias Commanded.EventStore
  alias Commanded.EventStore.SnapshotData

  describe "take snapshot" do
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
                 last_index: 10
               },
               metadata: nil,
               created_at: nil
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
                 last_index: 11
               },
               metadata: nil,
               created_at: nil
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
           last_index: 21
         },
         metadata: nil,
         created_at: nil
       }
    end
  end

  describe "restore snapshot" do
    test "should restore state from events when no snapshot" do
      aggregate_uuid = UUID.uuid4()
      append_items(aggregate_uuid, 1, snapshot_every: 10)
      restart_aggregate(aggregate_uuid)

      assert_aggregate_state aggregate_uuid, %ExampleAggregate{
        items: [1],
        last_index: 1
      }
      assert_aggregate_version aggregate_uuid, 1
    end

    test "should restore state from snapshot when present" do
      aggregate_uuid = UUID.uuid4()
      append_items(aggregate_uuid, 2, snapshot_every: 10)

      # record our own snapshot
      snapshot_aggregate(aggregate_uuid, 2, %ExampleAggregate{
        items: [],
      })

      restart_aggregate(aggregate_uuid)

      assert_aggregate_state aggregate_uuid, %ExampleAggregate{
        items: [],
      }
      assert_aggregate_version aggregate_uuid, 2
    end

    test "should restore state from snapshot and any newer events when present" do
      aggregate_uuid = UUID.uuid4()

      append_items(aggregate_uuid, 5, snapshot_every: 10)

      # record our own snapshot
      snapshot_aggregate(aggregate_uuid, 2, %ExampleAggregate{
        items: [],
        last_index: 2
      })

      restart_aggregate(aggregate_uuid)

      assert_aggregate_state aggregate_uuid, %ExampleAggregate{
        items: [3, 4, 5],
        last_index: 5
      }
      assert_aggregate_version aggregate_uuid, 5
    end
  end

  # assert aggregate's state equals the given expected state
  defp assert_aggregate_state(aggregate_uuid, expected_state) do
    assert Aggregate.aggregate_state(ExampleAggregate, aggregate_uuid) == expected_state
  end

  # assert aggregate's version equals the given expected version
  defp assert_aggregate_version(aggregate_uuid, expected_version) do
    assert Aggregate.aggregate_version(ExampleAggregate, aggregate_uuid) == expected_version
  end

  # restart the aggregate process
  defp restart_aggregate(aggregate_uuid) do
    assert :ok = Aggregate.shutdown(ExampleAggregate, aggregate_uuid)

    assert {:ok, ^aggregate_uuid} = Commanded.Aggregates.Supervisor.open_aggregate(ExampleAggregate, aggregate_uuid)
  end

  defp append_items(aggregate_uuid, count, snapshot_every: snapshot_every) do
    execution_context = %ExecutionContext{
      command: %AppendItems{count: count},
      handler: AppendItemsHandler,
      function: :handle,
      snapshot_every: snapshot_every
    }

    {:ok, ^aggregate_uuid} = Commanded.Aggregates.Supervisor.open_aggregate(ExampleAggregate, aggregate_uuid)

    {:ok, _count, _events} = Aggregate.execute(ExampleAggregate, aggregate_uuid, execution_context)
  end

  defp snapshot_aggregate(aggregate_uuid, aggregate_version, aggregate_state) do
    snapshot = %SnapshotData{
      source_uuid: aggregate_uuid,
      source_version: aggregate_version,
      source_type: Atom.to_string(aggregate_state.__struct__),
      data: aggregate_state,
    }

    :ok = Commanded.EventStore.record_snapshot(snapshot)
  end
end
