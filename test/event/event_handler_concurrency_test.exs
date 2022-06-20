defmodule Commanded.Event.EventHandlerConcurrencyTest do
  use ExUnit.Case

  alias Commanded.{DefaultApp, EventStore}
  alias Commanded.Event.{ConcurrencyEvent, ConcurrentEventHandler, Mapper, PartitionEventHandler}

  setup do
    true = Process.register(self(), :test)

    start_supervised!(DefaultApp)

    :ok
  end

  describe "concurrent event handler" do
    setup do
      supervisor = start_supervised!(ConcurrentEventHandler)

      [supervisor: supervisor]
    end

    test "should start one event handler per requested concurrency", %{supervisor: supervisor} do
      assert %{active: 5, specs: 5, supervisors: 0, workers: 5} =
               Supervisor.count_children(supervisor)

      children = Supervisor.which_children(supervisor)

      assert length(children) == 5

      children
      |> Enum.reverse()
      |> Enum.with_index()
      |> Enum.each(fn {child, index} ->
        assert match?(
                 {{ConcurrentEventHandler,
                   [
                     index: ^index,
                     application: Commanded.DefaultApp,
                     name: ConcurrentEventHandler,
                     concurrency: 5
                   ]}, pid, :worker, [ConcurrentEventHandler]}
                 when is_pid(pid),
                 child
               )
      end)
    end

    test "should call `init/0` callback function once for each started handler" do
      assert_receive {:init, pid1}
      assert_receive {:init, pid2}
      assert_receive {:init, pid3}
      assert_receive {:init, pid4}
      assert_receive {:init, pid5}
      refute_receive {:init, _pid}

      unique_pids = Enum.uniq([pid1, pid2, pid3, pid4, pid5])
      assert length(unique_pids) == 5
    end

    test "should call `init/1` callback function once for each started handler", %{
      supervisor: supervisor
    } do
      assert_receive {:init, config1, ^supervisor}
      assert_receive {:init, config2, ^supervisor}
      assert_receive {:init, config3, ^supervisor}
      assert_receive {:init, config4, ^supervisor}
      assert_receive {:init, config5, ^supervisor}
      refute_receive {:init, _config, _pid}

      [config1, config2, config3, config4, config5]
      |> Enum.with_index()
      |> Enum.each(fn {config, index} ->
        assert config == [
                 index: index,
                 application: Commanded.DefaultApp,
                 name: Commanded.Event.ConcurrentEventHandler,
                 concurrency: 5
               ]
      end)
    end

    test "should only receive an event once" do
      append_events_to_stream("stream1", count: 1)

      assert_receive {:event, "stream1", _pid}
      refute_receive {:event, _stream_uuid, _pid}
    end

    test "should distribute events amongst event handlers" do
      append_events_to_stream("stream1", count: 5)

      assert_receive {:event, "stream1", pid1}
      assert_receive {:event, "stream1", pid2}
      assert_receive {:event, "stream1", pid3}
      assert_receive {:event, "stream1", pid4}
      assert_receive {:event, "stream1", pid5}
      refute_receive {:event, _stream_uuid, _pid}

      unique_pids = Enum.uniq([pid1, pid2, pid3, pid4, pid5])
      assert length(unique_pids) == 5
    end

    test "should error when handler started with `:strong` consistency" do
      assert_raise ArgumentError,
                   "cannot use `:strong` consistency with concurrency",
                   fn -> ConcurrentEventHandler.start_link(consistency: :strong) end
    end
  end

  describe "concurrent event handler with partitioning" do
    setup do
      start_supervised!(PartitionEventHandler)

      :ok
    end

    test "should use optional `partition_by/2` callback function to partition events to handlers" do
      append_events_to_stream("stream1", count: 2, index: 1, partition: "partition1")
      append_events_to_stream("stream2", count: 2, index: 3, partition: "partition2")
      append_events_to_stream("stream3", count: 2, index: 5, partition: "partition3")

      assert_receive {:partition_by, %ConcurrencyEvent{index: 1, partition: "partition1"},
                      metadata}

      handler_name = inspect(PartitionEventHandler)

      assert match?(
               %{
                 application: DefaultApp,
                 handler_name: ^handler_name,
                 event_id: _event_id,
                 event_number: _event_number,
                 stream_id: "stream1",
                 stream_version: 1,
                 correlation_id: _correlation_id,
                 causation_id: _causation_id,
                 created_at: %DateTime{}
               },
               metadata
             )

      assert_receive {:event, "stream1", pid1}

      assert_receive {:partition_by, %ConcurrencyEvent{index: 2, partition: "partition1"}, %{}}
      assert_receive {:event, "stream1", pid2}

      assert_receive {:partition_by, %ConcurrencyEvent{index: 3, partition: "partition2"}, %{}}
      assert_receive {:event, "stream2", pid3}

      assert_receive {:partition_by, %ConcurrencyEvent{index: 4, partition: "partition2"}, %{}}
      assert_receive {:event, "stream2", pid4}

      assert_receive {:partition_by, %ConcurrencyEvent{index: 5, partition: "partition3"}, %{}}
      assert_receive {:event, "stream3", pid5}

      assert_receive {:partition_by, %ConcurrencyEvent{index: 6, partition: "partition3"}, %{}}
      assert_receive {:event, "stream3", pid6}

      refute_receive {:event, _stream_uuid, _pid}

      unique_pids = Enum.uniq([pid1, pid2, pid3, pid4, pid5, pid6])
      assert length(unique_pids) == 3
    end
  end

  test "should raise an argument error when invalid concurrency option provided" do
    assert_raise ArgumentError,
                 "invalid `:concurrency` for event handler, expected a positive integer but got: :invalid",
                 fn -> start_supervised!({ConcurrentEventHandler, concurrency: :invalid}) end
  end

  defp append_events_to_stream(stream_uuid, opts) do
    index = Keyword.get(opts, :index, 1)
    count = Keyword.get(opts, :count, 1) + index - 1

    events =
      Enum.map(index..count, fn index ->
        %ConcurrencyEvent{
          stream_uuid: stream_uuid,
          index: index,
          partition: Keyword.get(opts, :partition)
        }
      end)
      |> Mapper.map_to_event_data()

    EventStore.append_to_stream(DefaultApp, stream_uuid, :any_version, events)
  end
end
