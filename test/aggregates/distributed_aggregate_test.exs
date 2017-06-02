defmodule Commanded.Entities.DistributedAggregateTest do
  use Commanded.StorageCase
  use Commanded.EventStore

  alias Commanded.ExampleDomain.BankAccount
  alias Commanded.Aggregates.DistributedAggregate

  defmodule ExampleAggregate do
    defstruct [id: "f4156f72-2d19-48b1-bf3e-705075111072", name: "John Smith",
               msg: "Just created", widget_count: 0]
  end

  defimpl DistributedAggregate, for: Commanded.Entities.DistributedAggregateTest.ExampleAggregate do
    def begin_handoff(state) do
      {:resume, state}
    end

    def end_handoff(current_state, handoff_state) do
      %{current_state | widget_count: handoff_state.widget_count}
    end

    def resolve_conflict(current_state, conflicting_state) do
      %{current_state | msg: conflicting_state.msg}
    end

    def cleanup(state) do
      {:stop, :shutdown, state}
    end
  end

  describe "BankAccount aggregate started" do
    setup do
      aggregate_uuid = UUID.uuid4

      {:ok, ^aggregate_uuid} = Commanded.Aggregates.Supervisor.open_aggregate(BankAccount, aggregate_uuid)

      pid = Swarm.whereis_name(aggregate_uuid)
      ref = Process.monitor(pid)

      %{aggregate_uuid: aggregate_uuid, pid: pid, ref: ref}
    end

    test "default DistributedAggregate should return {:restart} if handoff initiated", fixture do
      {:restart} = GenServer.call(fixture.pid, {:swarm, :begin_handoff});
    end

    test "default DistributedAggregate :end_handoff messages should raise exception", %{pid: pid, ref: ref} do
      :ok = GenServer.cast(pid, {:swarm, :end_handoff, %{foo: "bar"}})
      assert_receive({:DOWN, ^ref, :process, _, _}, 30)
    end

    test "default DistributedAggregate should ignore Swarm :resolve_conflict messages", %{pid: pid, aggregate_uuid: aggregate_uuid} do
      existing_state = Commanded.Aggregates.Aggregate.aggregate_state(aggregate_uuid)
      :ok = GenServer.cast(pid, {:swarm, :resolve_conflict, %BankAccount{balance: 12}})
      new_state = Commanded.Aggregates.Aggregate.aggregate_state(aggregate_uuid)
      assert existing_state == new_state
    end

    test "default DistributedAggrgate should issue :shutdown when receiving {:swarm, :die} message", %{pid: pid, ref: ref} do
      send(pid, {:swarm, :die})
      assert_receive({:DOWN, ^ref, :process, _, :shutdown})
    end
  end

  describe "ExampleAggregate started" do
    setup do
      aggregate_uuid = UUID.uuid4

      {:ok, ^aggregate_uuid} = Commanded.Aggregates.Supervisor.open_aggregate(ExampleAggregate, aggregate_uuid)

      pid = Swarm.whereis_name(aggregate_uuid)
      ref = Process.monitor(pid)

      %{aggregate_uuid: aggregate_uuid, pid: pid, ref: ref}
    end

    test "should initiate handoff of current state", %{pid: pid} do
      {:resume, %ExampleAggregate{id: "f4156f72-2d19-48b1-bf3e-705075111072"}} = GenServer.call(pid, {:swarm, :begin_handoff});
    end

    test "{:swarm, :end_handoff} should add passed state to current state", %{pid: pid, aggregate_uuid: aggregate_uuid} do
      GenServer.cast(pid, {:swarm, :end_handoff, %ExampleAggregate{widget_count: 12}})
      %ExampleAggregate{widget_count: 12} = Commanded.Aggregates.Aggregate.aggregate_state(aggregate_uuid)
    end

    test "{:swarm, :resolve_conflict} should accept new state and modify existing state", %{pid: pid, aggregate_uuid: aggregate_uuid} do
      GenServer.cast(pid, {:swarm, :resolve_conflict, %ExampleAggregate{msg: "conflicting message"}})
      %ExampleAggregate{msg: "conflicting message"} = Commanded.Aggregates.Aggregate.aggregate_state(aggregate_uuid)
    end
  end
end
