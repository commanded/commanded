defmodule Commanded.EventAssertionsTest do
  use ExUnit.Case

  import Commanded.Assertions.EventAssertions

  alias Commanded.{DefaultApp, EventStore}
  alias Commanded.Event.Mapper

  defmodule Event do
    @derive Jason.Encoder
    defstruct [:data]
  end

  defmodule AnotherEvent do
    @derive Jason.Encoder
    defstruct [:data]
  end

  setup do
    start_supervised!(DefaultApp)
    :ok
  end

  describe "assert_receive_event/2" do
    test "should succeed when event received" do
      append_events("stream1", [%AnotherEvent{data: 1}, %Event{data: 1}])

      assert_receive_event(DefaultApp, Event, fn %Event{data: data} -> assert data == 1 end)
    end

    test "should fail when no events received" do
      assert_raise ExUnit.AssertionError, fn ->
        assert_receive_event(DefaultApp, Event, fn %Event{data: data} -> assert data == 1 end)
      end
    end

    test "should fail when event not received" do
      append_events("stream1", [%AnotherEvent{data: 1}])

      assert_raise ExUnit.AssertionError, fn ->
        assert_receive_event(DefaultApp, Event, fn %Event{data: data} -> assert data == 1 end)
      end
    end

    test "should fail when unknown event type" do
      assert_raise ExUnit.AssertionError, "\n\nEvent Unknown not found\n", fn ->
        assert_receive_event(DefaultApp, Unknown, fn _event -> assert true end)
      end
    end
  end

  describe "assert_receive_event/3" do
    test "should succeed when event received" do
      append_events("stream1", [%Event{data: 1}])
      append_events("stream1", [%AnotherEvent{data: 1}])
      append_events("stream2", [%Event{data: 2}])
      append_events("stream3", [%Event{data: 3}])

      assert_receive_event(
        DefaultApp,
        Event,
        fn %Event{data: data} -> data == 2 end,
        fn %Event{data: data} ->
          assert data == 2
        end
      )
    end

    test "should fail when event not received" do
      assert_raise ExUnit.AssertionError, fn ->
        assert_receive_event(
          DefaultApp,
          Event,
          fn %Event{data: data} -> data == 2 end,
          fn %Event{data: data} ->
            assert data == 2
          end
        )
      end
    end
  end

  describe "refute_receive_event/1" do
    test "should succeed when event not received" do
      refute_receive_event(DefaultApp, Event, fn ->
        append_events("stream1", [%AnotherEvent{data: 1}])
      end)
    end

    test "should succeed when event not received matching predicate" do
      refute_receive_event(
        DefaultApp,
        Event,
        fn ->
          append_events("stream1", [%Event{data: 1}, %Event{data: 2}])
        end,
        predicate: fn %Event{data: data} -> data == 3 end
      )
    end

    test "should ignore events appending to another stream" do
      append_events("stream1", [%Event{data: 1}])

      refute_receive_event(
        DefaultApp,
        Event,
        fn ->
          append_events("stream1", [%AnotherEvent{data: 2}])
          append_events("stream2", [%Event{data: 2}])
        end,
        stream: "stream1"
      )
    end

    test "should ignore events previously appended to stream" do
      append_events("stream1", [%Event{data: 1}])

      refute_receive_event(DefaultApp, Event, fn ->
        append_events("stream1", [%AnotherEvent{data: 2}])
      end)
    end

    test "should fail when event received" do
      assert_raise ExUnit.AssertionError,
                   "\n\nUnexpectedly received event: #{inspect(%Event{data: 1})}\n",
                   fn ->
                     refute_receive_event(DefaultApp, Event, fn ->
                       append_events("stream1", [%Event{data: 1}])
                     end)
                   end
    end

    test "should fail when event received on stream" do
      assert_raise ExUnit.AssertionError,
                   "\n\nUnexpectedly received event: #{inspect(%Event{data: 1})}\n",
                   fn ->
                     refute_receive_event(
                       DefaultApp,
                       Event,
                       fn ->
                         append_events("stream1", [%AnotherEvent{data: 1}])
                         append_events("stream2", [%Event{data: 1}])
                       end,
                       stream: "stream2"
                     )
                   end
    end

    test "should fail when event received matching predicate" do
      assert_raise ExUnit.AssertionError,
                   "\n\nUnexpectedly received event: #{inspect(%Event{data: 3})}\n",
                   fn ->
                     refute_receive_event(
                       DefaultApp,
                       Event,
                       fn ->
                         append_events("stream1", [
                           %Event{data: 1},
                           %Event{data: 2},
                           %Event{data: 3}
                         ])
                       end,
                       predicate: fn %Event{data: data} -> data == 3 end
                     )
                   end
    end
  end

  defp append_events(stream_uuid, events) do
    event_data = Mapper.map_to_event_data(events)

    EventStore.append_to_stream(DefaultApp, stream_uuid, :any_version, event_data)
  end
end
