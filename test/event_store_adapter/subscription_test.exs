defmodule Commanded.EventStore.Adapter.SubscriptionTest do
  use Commanded.StorageCase
  use Commanded.EventStore

  alias Commanded.EventStore.{
    EventData,
    SnapshotData,
  }
  alias Commanded.ExampleDomain.BankAccount.Events.BankAccountOpened

  require Logger

  @tag :wip
  test "should subscribe to all streams" do
    {:ok, subscription} = @event_store.subscribe_to_all_streams("subscription-name", self(), :origin)

    {:ok, 1} = @event_store.append_to_stream("stream1", 0, build_events(1))
    {:ok, 2} = @event_store.append_to_stream("stream2", 0, build_events(2))
    {:ok, 3} = @event_store.append_to_stream("stream3", 0, build_events(3))

    assert_receive_events(subscription, 1)
    assert_receive_events(subscription, 2)
    assert_receive_events(subscription, 3)

    refute_receive({:events, _events})
  end

  def assert_receive_events(subscription, expected_count) do
    assert_receive {:events, received_events}
    assert length(received_events) == expected_count

    @event_store.ack_event(subscription, List.last(received_events))
  end

  # test "should prevent duplicate subscriptions"
  # test "should catch-up from existing events"
  # test "should remember last seen event number when subscription resumes"
  
  # test "should unsubscribe from all streams" do
  #   subscriber_task = Task.async fn ->
  #     loop = fn(ev_count, loop_fn) ->
	# receive do
	#   {:events, events, subscription} ->
	#     @event_store.ack_event(subscription, List.last(events))
  #
	#     loop_fn.(ev_count + length(events), loop_fn)
	#   :exit -> ev_count
	#   ev ->
	#     Logger.debug(fn -> "received non expected event: #{inspect ev}" end)
	#     assert false
	# end
  #     end
  #
  #     loop.(0, loop)
  #   end
  #
  #   {:ok, 4} = @event_store.append_to_stream("astream1", 0, build_events(4))
  #
  #   {:ok, _subscription} = @event_store.subscribe_to_all_streams("sub1", subscriber_task.pid)
  #
  #   {:ok, 3} = @event_store.append_to_stream("astream2", 0, build_events(3))
  #
  #   :timer.sleep(400) # give subscriber a chance to receive events
  #   assert :ok = @event_store.unsubscribe_from_all_streams("sub1")
  #
  #   {:ok, 6} = @event_store.append_to_stream("astream2", 3, build_events(3))
  #
  #   :timer.sleep(400) # give subscriber a chance to receive events
  #   send(subscriber_task.pid, :exit)
  #
  #   assert 7 == Task.await(subscriber_task, 2_000)
  # end
  #
  # if @event_store == Commanded.EventStore.Adapters.ExtremeEventStore do
  #   test "back pressure" do
  #     count = 20
  #     test_events = build_events(count)
  #     {:ok, count} = @event_store.append_to_stream("astream1", 0, test_events)
  #
  #     subscriber_task = Task.async fn ->
	# loop = fn(evs, loop_fn) ->
	#   receive do
	#     {:events, events, subscription} ->
	#       evs = events ++ evs
	#       {:messages, messages} = Process.info(self(), :messages)
	#       queue_len = length(messages)
  #
	#       :timer.sleep(100)
	#       assert queue_len < 11
	#       @event_store.ack_event(subscription, List.last(events))
  #
	#       if length(evs) < count, do: loop_fn.(evs, loop_fn), else: evs
	#     :exit -> evs
	#   end
	# end
  #
	# loop.([], loop)
  #     end
  #
  #     @event_store.subscribe_to_all_streams("sub1", subscriber_task.pid, :origin, [max_buffer_size: 10])
  #
  #     received_events = Task.await(subscriber_task, 3_000)
  #     assert Enum.map(test_events, &(&1.data)) == Enum.map(Enum.reverse(received_events), &(&1.data))
  #   end
  #
  #   test "should read from soft deleted stream" do
  #     events = build_events 10
  #     ev_batch1 = Enum.slice(events, 0, 5)
  #     ev_batch2 = Enum.slice(events, 5, 5)
  #     coerce = fn(evs) -> Enum.map(evs, &(%{correlation_id: &1.correlation_id, data: &1.data})) end
  #
  #     assert {:ok, 5} == @event_store.append_to_stream("astream", 0, ev_batch1)
  #
  #     {:ok, result } = @event_store.read_stream_forward("astream", 1, 10)
  #     assert coerce.(ev_batch1) == coerce.(result)
  #
  #     @event_store.delete_stream("astream")
  #     assert {:ok, 10} == @event_store.append_to_stream("astream", :any_version, ev_batch2)
  #
  #     {:ok, result } = @event_store.read_stream_forward("astream", 1, 7)
  #     assert length(ev_batch2) == length(result)
  #     assert coerce.(ev_batch2) == coerce.(result)
  #   end
  # end


  defp build_event(account_number) do
    %EventData{
      correlation_id: UUID.uuid4,
      event_type: "Elixir.Commanded.ExampleDomain.BankAccount.Events.BankAccountOpened",
      data: %BankAccountOpened{account_number: account_number, initial_balance: 1_000},
      metadata: %{}
    }
  end

  defp build_events(count) do
    for account_number <- 1..count, do: build_event(account_number)
  end
end
