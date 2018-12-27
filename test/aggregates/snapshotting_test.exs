defmodule Commanded.Aggregates.SnapshottingTest do
  use Commanded.StorageCase

  alias Commanded.Aggregates.{
    Aggregate,
    AppendItemsHandler,
    ExampleAggregate,
    ExecutionContext,
    SnapshotAggregate,
    Supervisor
  }

  alias Commanded.Aggregates.ExampleAggregate.Commands.AppendItems
  alias Commanded.Aggregates.SnapshotAggregate.Commands.Create
  alias Commanded.EventStore
  alias Commanded.EventStore.SnapshotData

  setup do
    on_exit(fn ->
      unconfigure_snapshotting(ExampleAggregate)
    end)
  end

  describe "with snapshotting disabled" do
    setup do
      configure_snapshotting(ExampleAggregate, snapshot_every: nil)
    end

    test "should not shapshot" do
      aggregate_uuid = UUID.uuid4()
      append_items(aggregate_uuid, 1)

      assert EventStore.read_snapshot(aggregate_uuid) == {:error, :snapshot_not_found}
    end

    test "should ignore existing snapshot" do
      aggregate_uuid = UUID.uuid4()
      append_items(aggregate_uuid, 2)

      # record our own snapshot
      snapshot_aggregate(aggregate_uuid, 2, %ExampleAggregate{
        items: []
      })

      restart_aggregate(ExampleAggregate, aggregate_uuid)

      assert_aggregate_state(ExampleAggregate, aggregate_uuid, %ExampleAggregate{
        items: [1, 2],
        last_index: 2
      })

      assert_aggregate_version(ExampleAggregate, aggregate_uuid, 2)
    end
  end

  describe "with zero shapshot interval" do
    setup do
      configure_snapshotting(ExampleAggregate, snapshot_every: 0)
    end

    test "should not shapshot when set to 0" do
      aggregate_uuid = UUID.uuid4()
      append_items(aggregate_uuid, 1)

      assert EventStore.read_snapshot(aggregate_uuid) == {:error, :snapshot_not_found}
    end
  end

  describe "with snapshotting configured" do
    setup do
      configure_snapshotting(ExampleAggregate, snapshot_every: 10)
    end

    test "should not shapshot when fewer snapshot interval" do
      aggregate_uuid = UUID.uuid4()
      append_items(aggregate_uuid, 9)

      assert EventStore.read_snapshot(aggregate_uuid) == {:error, :snapshot_not_found}
    end

    test "should shapshot when exactly snapshot interval" do
      aggregate_uuid = UUID.uuid4()
      append_items(aggregate_uuid, 10)

      assert_aggregate_version(ExampleAggregate, aggregate_uuid, 10)

      assert {:ok, snapshot} = EventStore.read_snapshot(aggregate_uuid)

      assert snapshot == %SnapshotData{
               source_uuid: aggregate_uuid,
               source_version: 10,
               source_type: "Elixir.Commanded.Aggregates.ExampleAggregate",
               data: %ExampleAggregate{
                 items: Enum.to_list(1..10),
                 last_index: 10
               },
               metadata: %{"snapshot_module_version" => 1}
             }
    end

    test "should shapshot when more than snapshot interval" do
      aggregate_uuid = UUID.uuid4()
      append_items(aggregate_uuid, 11)

      assert_aggregate_version(ExampleAggregate, aggregate_uuid, 11)

      assert {:ok, snapshot} = EventStore.read_snapshot(aggregate_uuid)

      assert snapshot == %SnapshotData{
               source_uuid: aggregate_uuid,
               source_version: 11,
               source_type: "Elixir.Commanded.Aggregates.ExampleAggregate",
               data: %ExampleAggregate{
                 items: Enum.to_list(1..11),
                 last_index: 11
               },
               metadata: %{"snapshot_module_version" => 1}
             }
    end

    test "should shapshot again when interval reached" do
      aggregate_uuid = UUID.uuid4()

      append_items(aggregate_uuid, 10)
      assert_aggregate_version(ExampleAggregate, aggregate_uuid, 10)
      assert {:ok, snapshot} = EventStore.read_snapshot(aggregate_uuid)
      assert snapshot.source_version == 10

      append_items(aggregate_uuid, 1)
      assert_aggregate_version(ExampleAggregate, aggregate_uuid, 11)
      assert {:ok, snapshot} = EventStore.read_snapshot(aggregate_uuid)
      assert snapshot.source_version == 10

      append_items(aggregate_uuid, 10)
      assert_aggregate_version(ExampleAggregate, aggregate_uuid, 21)
      assert {:ok, snapshot} = EventStore.read_snapshot(aggregate_uuid)

      assert snapshot == %SnapshotData{
               source_uuid: aggregate_uuid,
               source_version: 21,
               source_type: "Elixir.Commanded.Aggregates.ExampleAggregate",
               data: %ExampleAggregate{
                 items: Enum.to_list(1..21),
                 last_index: 21
               },
               metadata: %{"snapshot_module_version" => 1}
             }
    end
  end

  describe "restore snapshot" do
    setup do
      configure_snapshotting(ExampleAggregate, snapshot_every: 10)
    end

    test "should restore state from events when no snapshot" do
      aggregate_uuid = UUID.uuid4()
      append_items(aggregate_uuid, 1)
      restart_aggregate(ExampleAggregate, aggregate_uuid)

      assert_aggregate_state(ExampleAggregate, aggregate_uuid, %ExampleAggregate{
        items: [1],
        last_index: 1
      })

      assert_aggregate_version(ExampleAggregate, aggregate_uuid, 1)
    end

    test "should restore state from snapshot when present" do
      aggregate_uuid = UUID.uuid4()
      append_items(aggregate_uuid, 2)

      # record our own snapshot
      snapshot_aggregate(aggregate_uuid, 2, %ExampleAggregate{
        items: []
      })

      restart_aggregate(ExampleAggregate, aggregate_uuid)

      assert_aggregate_state(ExampleAggregate, aggregate_uuid, %ExampleAggregate{
        items: []
      })

      assert_aggregate_version(ExampleAggregate, aggregate_uuid, 2)
    end

    test "should restore state from snapshot and any newer events when present" do
      aggregate_uuid = UUID.uuid4()
      append_items(aggregate_uuid, 5)

      # record our own snapshot
      snapshot_aggregate(aggregate_uuid, 2, %ExampleAggregate{
        items: [],
        last_index: 2
      })

      restart_aggregate(ExampleAggregate, aggregate_uuid)

      assert_aggregate_state(ExampleAggregate, aggregate_uuid, %ExampleAggregate{
        items: [3, 4, 5],
        last_index: 5
      })

      assert_aggregate_version(ExampleAggregate, aggregate_uuid, 5)
    end
  end

  describe "mismatched snapshot versions" do
    setup do
      configure_snapshotting(ExampleAggregate, snapshot_every: 10, snapshot_version: 2)
    end

    test "should ignore older snapshot versions" do
      aggregate_uuid = UUID.uuid4()
      append_items(aggregate_uuid, 2)

      # record an outdated snapshot
      snapshot_aggregate(
        aggregate_uuid,
        1,
        %ExampleAggregate{
          items: []
        },
        %{"snapshot_module_version" => 1}
      )

      restart_aggregate(ExampleAggregate, aggregate_uuid)

      # aggregate state should ignore snapshot and rebuild from events
      assert_aggregate_state(ExampleAggregate, aggregate_uuid, %ExampleAggregate{
        items: [1, 2],
        last_index: 2
      })

      assert_aggregate_version(ExampleAggregate, aggregate_uuid, 2)
    end
  end

  describe "decode snapshot data" do
    setup do
      configure_snapshotting(SnapshotAggregate, snapshot_every: 1, snapshot_version: 1)
    end

    test "should parse date" do
      aggregate_uuid = UUID.uuid4()
      now = NaiveDateTime.utc_now()

      create_aggregate(aggregate_uuid, now)
      restart_aggregate(SnapshotAggregate, aggregate_uuid)

      # aggregate state should be decoded
      assert_aggregate_state(SnapshotAggregate, aggregate_uuid, %SnapshotAggregate{
        name: "Example",
        date: NaiveDateTime.to_iso8601(now)
      })

      assert_aggregate_version(SnapshotAggregate, aggregate_uuid, 1)
    end

    defp create_aggregate(aggregate_uuid, %NaiveDateTime{} = date) do
      execution_context = %ExecutionContext{
        command: %Create{name: "Example", date: date},
        handler: SnapshotAggregate,
        function: :execute
      }

      {:ok, ^aggregate_uuid} = Supervisor.open_aggregate(SnapshotAggregate, aggregate_uuid)

      {:ok, _count, _events} =
        Aggregate.execute(SnapshotAggregate, aggregate_uuid, execution_context)
    end
  end

  # assert aggregate's state equals the given expected state
  defp assert_aggregate_state(aggregate_module, aggregate_uuid, expected_state) do
    assert Aggregate.aggregate_state(aggregate_module, aggregate_uuid) == expected_state
  end

  # assert aggregate's version equals the given expected version
  defp assert_aggregate_version(aggregate_module, aggregate_uuid, expected_version) do
    assert Aggregate.aggregate_version(aggregate_module, aggregate_uuid) == expected_version
  end

  # restart the aggregate process
  defp restart_aggregate(aggregate_module, aggregate_uuid) do
    assert :ok = Aggregate.shutdown(aggregate_module, aggregate_uuid)

    assert {:ok, ^aggregate_uuid} = Supervisor.open_aggregate(aggregate_module, aggregate_uuid)
  end

  defp configure_snapshotting(aggregate_module, opts) do
    Application.put_env(:commanded, aggregate_module, opts)
  end

  defp unconfigure_snapshotting(aggregate_module) do
    Application.delete_env(:commanded, aggregate_module)
  end

  defp append_items(aggregate_uuid, count) do
    execution_context = %ExecutionContext{
      command: %AppendItems{count: count},
      handler: AppendItemsHandler,
      function: :handle
    }

    {:ok, ^aggregate_uuid} = Supervisor.open_aggregate(ExampleAggregate, aggregate_uuid)

    {:ok, _count, _events} =
      Aggregate.execute(ExampleAggregate, aggregate_uuid, execution_context)
  end

  defp snapshot_aggregate(aggregate_uuid, aggregate_version, aggregate_state, metadata \\ %{})

  defp snapshot_aggregate(aggregate_uuid, aggregate_version, aggregate_state, metadata) do
    snapshot = %SnapshotData{
      source_uuid: aggregate_uuid,
      source_version: aggregate_version,
      source_type: Atom.to_string(aggregate_state.__struct__),
      data: aggregate_state,
      metadata: metadata
    }

    :ok = Commanded.EventStore.record_snapshot(snapshot)
  end
end
