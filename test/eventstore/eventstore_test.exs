defmodule Commanded.EventStore.EventStoreTest do
  use Commanded.StorageCase
  use Commanded.EventStore

  alias Commanded.EventStore.{EventData, SnapshotData}
  alias Commanded.ExampleDomain.BankAccount.Events.BankAccountOpened

  require Logger

  defp create_test_event(account_number) do
    %EventData{
      correlation_id: UUID.uuid4,
      event_type: "Elixir.Commanded.ExampleDomain.BankAccount.Events.BankAccountOpened",
      data: %BankAccountOpened{account_number: account_number, initial_balance: 1_000},
      metadata: nil
    }
  end

  defp new_test_events(count) do
    for account_number <- 1..count do
      create_test_event(account_number)
    end
  end

  defp create_snapshot_data(account_number) do
    %SnapshotData{
      source_uuid: UUID.uuid4,
      source_version: account_number,
      source_type: "Elixir.Commanded.ExampleDomain.BankAccount.Events.BankAccountOpened",
      data:  %BankAccountOpened{account_number: account_number, initial_balance: 1_000},
      metadata: nil,
      created_at: DateTime.to_naive(DateTime.utc_now())
    }    
  end

  defp snapshot_created_at_seconds_to_zero(snapshot) do
    %NaiveDateTime{year: year, month: month, day: day, hour: hour, minute: min} = snapshot.created_at
    {:ok, zeroed_created_at} = NaiveDateTime.new(year, month, day, hour, min, 0, 0)

    %SnapshotData{snapshot | created_at: zeroed_created_at}
  end

  test "should append an event to a stream" do
    assert {:ok, 2} == @event_store.append_to_stream("astream", 0, new_test_events(2))
    assert {:ok, 4} == @event_store.append_to_stream("astream", 2, new_test_events(2))
    assert {:ok, 5} == @event_store.append_to_stream("astream", 4, new_test_events(1))
  end

  test "should fail to append to a stream because of wrong expected version" do
    events = new_test_events 1

    assert {:error, :wrong_expected_version} == @event_store.append_to_stream("astream", 1, events)
  end

  test "should read from a stream" do
    events = new_test_events 4
    coerce = fn(evs) -> Enum.map(evs, &(%{correlation_id: &1.correlation_id, data: &1.data})) end

    assert {:ok, 4} == @event_store.append_to_stream("astream", 0, events)

    {:ok, result } = @event_store.read_stream_forward("astream", 1)
    assert coerce.(events) == coerce.(result)

    {:ok, result } = @event_store.read_stream_forward("astream", 3)
    assert coerce.(Enum.slice(events, 2, 2)) == coerce.(result)
  end

  test "should read from all streams" do
    events1 = new_test_events 4
    events2 = new_test_events 4
    coerce = fn(evs) -> Enum.map(evs, &(%{correlation_id: &1.correlation_id, data: &1.data})) end

    assert {:ok, 4} == @event_store.append_to_stream("astream", 0, events1)
    assert {:ok, 4} == @event_store.append_to_stream("asecondstream", 0, events2)

    :timer.sleep(500)

    {:ok, result } = @event_store.read_all_streams_forward(0)

    assert 8 == length(result)
    assert coerce.(events1 ++ events2) == coerce.(result)
  end

  test "should record a snapshot" do
    snapshot = create_snapshot_data(100)

    assert :ok = @event_store.record_snapshot(snapshot)
  end

  test "should read a snapshot" do
    snapshot1 = create_snapshot_data(100)
    snapshot2 = create_snapshot_data(101)
    snapshot3 = create_snapshot_data(102)

    assert :ok == @event_store.record_snapshot(snapshot1)
    assert :ok == @event_store.record_snapshot(snapshot2)
    assert :ok == @event_store.record_snapshot(snapshot3)

    {:ok, snapshot} = @event_store.read_snapshot(snapshot3.source_uuid)
    assert snapshot_created_at_seconds_to_zero(snapshot) == snapshot_created_at_seconds_to_zero(snapshot3)
  end

  test "should delete a snapshot" do
    snapshot1 = create_snapshot_data(100)

    assert :ok == @event_store.record_snapshot(snapshot1)
    {:ok, snapshot} = @event_store.read_snapshot(snapshot1.source_uuid)
    assert snapshot_created_at_seconds_to_zero(snapshot) == snapshot_created_at_seconds_to_zero(snapshot1)

    assert :ok == @event_store.delete_snapshot(snapshot1.source_uuid)
    assert {:error, :snapshot_not_found} == @event_store.read_snapshot(snapshot1.source_uuid)
  end

  test "should subscribe to all streams" do
    subscriber_task = Task.async fn ->
      loop = fn(ev_count, loop_fn) ->
	receive do
	  {:events, events, subscription} ->
	    for ev <- events do
	      assert(ev.data.account_number == 1)
	    end
	    ev_count = ev_count + length(events)

	    send(subscription, {:ack, List.last(events).event_id})

	    if (ev_count < 3), do: loop_fn.(ev_count, loop_fn), else: ev_count
	  ev ->
	    Logger.debug(fn -> "received non expected event: #{inspect ev}" end)
	    assert false
	end
      end

      loop.(0, loop)
    end
    {:ok, _subscription} = @event_store.subscribe_to_all_streams("subscription-name", subscriber_task.pid)

    {:ok, 1} = @event_store.append_to_stream("astream1", 0, new_test_events(1))
    {:ok, 1} = @event_store.append_to_stream("astream2", 0, new_test_events(1))
    {:ok, 1} = @event_store.append_to_stream("astream3", 0, new_test_events(1))

    assert 3 == Task.await(subscriber_task, 2_000)
  end

  @tag :wip
  test "should unsubscribe from all streams" do
    subscriber_task = Task.async fn ->
      loop = fn(ev_count, loop_fn) ->
	receive do
	  {:events, events, subscription} ->
	    send(subscription, {:ack, List.last(events).event_id})

	    loop_fn.(ev_count + length(events), loop_fn)
	  :exit -> ev_count
	  ev ->
	    Logger.debug(fn -> "received non expected event: #{inspect ev}" end)
	    assert false
	end
      end

      loop.(0, loop)
    end

    {:ok, 4} = @event_store.append_to_stream("astream1", 0, new_test_events(4))

    {:ok, _subscription} = @event_store.subscribe_to_all_streams("sub1", subscriber_task.pid)

    {:ok, 3} = @event_store.append_to_stream("astream2", 0, new_test_events(3))

    :timer.sleep(400) # give subscriber a chance to receive events
    assert :ok = @event_store.unsubscribe_from_all_streams("sub1")

    {:ok, 6} = @event_store.append_to_stream("astream2", 3, new_test_events(3))

    :timer.sleep(400) # give subscriber a chance to receive events
    send(subscriber_task.pid, :exit)

    assert 7 == Task.await(subscriber_task, 2_000)
  end
end
