defmodule Commanded.Aggregates.AggregateStateTest do
  use ExUnit.Case

  alias Commanded.DefaultApp

  alias Commanded.Aggregates.{
    Aggregate,
    AppendItemsHandler,
    ExampleAggregate,
    ExecutionContext,
    Supervisor
  }

  alias Commanded.Aggregates.ExampleAggregate.Commands.AppendItems
  alias Commanded.UUID

  @aggregate_module ExampleAggregate

  setup do
    start_supervised!({DefaultApp, snapshotting: %{ExampleAggregate => [snapshot_every: 10]}})

    :ok
  end

  test "query aggregate_state from the running aggregate gen_server" do
    aggregate_uuid = UUID.uuid4()
    append_items(aggregate_uuid, 9)

    assert_aggregate_version(aggregate_uuid, 9)
    assert_aggregate_state(aggregate_uuid, 9)
  end

  test "get aggregate_state by querying the state snapshot" do
    aggregate_uuid = UUID.uuid4()
    append_items(aggregate_uuid, 10)

    assert_aggregate_version(aggregate_uuid, 10)
    stop_aggregate(aggregate_uuid)
    assert_aggregate_state(aggregate_uuid, 10)
  end

  test "get aggregate_state by querying the state snapshot and rebuilding from events" do
    aggregate_uuid = UUID.uuid4()
    append_items(aggregate_uuid, 11)

    assert_aggregate_version(aggregate_uuid, 11)
    stop_aggregate(aggregate_uuid)

    assert_aggregate_state(aggregate_uuid, 11)
  end

  test "get aggregate_state by rebuilding from events" do
    aggregate_uuid = UUID.uuid4()
    append_items(aggregate_uuid, 9)

    assert_aggregate_version(aggregate_uuid, 9)
    stop_aggregate(aggregate_uuid)

    assert_aggregate_state(aggregate_uuid, 9)
  end

  # Assert aggregate's state equals the given expected state.
  defp assert_aggregate_state(aggregate_uuid, last_index) do
    assert Aggregate.aggregate_state(DefaultApp, @aggregate_module, aggregate_uuid) ==
             %@aggregate_module{
               items: Enum.to_list(1..last_index),
               last_index: last_index
             }
  end

  # Assert aggregate's version equals the given expected version.
  defp assert_aggregate_version(aggregate_uuid, expected_version) do
    assert Aggregate.aggregate_version(DefaultApp, @aggregate_module, aggregate_uuid) ==
             expected_version
  end

  # Shutdown the aggregate process
  defp stop_aggregate(aggregate_uuid) do
    assert :ok = Aggregate.shutdown(DefaultApp, @aggregate_module, aggregate_uuid)
  end

  defp append_items(aggregate_uuid, count) do
    execution_context = %ExecutionContext{
      command: %AppendItems{count: count},
      handler: AppendItemsHandler,
      function: :handle
    }

    {:ok, ^aggregate_uuid} =
      Supervisor.open_aggregate(DefaultApp, @aggregate_module, aggregate_uuid)

    {:ok, _count, _events} =
      Aggregate.execute(DefaultApp, @aggregate_module, aggregate_uuid, execution_context)
  end
end
