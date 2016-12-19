defmodule EventStore.Streams.StreamTest do
  use EventStore.StorageCase
  doctest EventStore.Streams.Supervisor
  doctest EventStore.Streams.Stream

  alias EventStore.EventFactory
  alias EventStore.ProcessHelper
  alias EventStore.Streams
  alias EventStore.Streams.Stream

  @subscription_name "test_subscription"

  test "open a stream" do
    stream_uuid = UUID.uuid4

    {:ok, stream} = Streams.open_stream(stream_uuid)

    assert stream != nil
  end

  test "open the same stream twice" do
    stream_uuid = UUID.uuid4

    {:ok, stream1} = Streams.open_stream(stream_uuid)
    {:ok, stream2} = Streams.open_stream(stream_uuid)

    assert stream1 != nil
    assert stream2 != nil
    assert stream1 == stream2
  end

  test "stream crash should allow restarting stream process" do
    stream_uuid = UUID.uuid4

    {:ok, stream} = Streams.open_stream(stream_uuid)

    ProcessHelper.shutdown(stream)

    {:ok, stream} = Streams.open_stream(stream_uuid)
    assert stream != nil
  end

  describe "append events to stream" do
    setup [:append_events_to_stream]

    test "should persist events", context do
      {:ok, events} = Stream.read_stream_forward(context[:stream], 0, 1_000)

      assert length(events) == 3
    end

    test "should set created at datetime", context do
      now = DateTime.utc_now |> DateTime.to_naive

      {:ok, [event]} = Stream.read_stream_forward(context[:stream], 0, 1)

      created_at = event.created_at
      assert created_at != nil
      assert created_at.year == now.year
      assert created_at.month == now.month
      assert created_at.day == now.day
      assert created_at.hour == now.hour
      assert created_at.minute == now.minute
    end

    test "for wrong expected version should error", context do
      {:error, :wrong_expected_version} = Stream.append_to_stream(context[:stream], 0, context[:events])
    end
  end

  test "attempt to read an unknown stream forward should error stream not found" do
    unknown_stream_uuid = UUID.uuid4
    {:ok, stream} = Streams.open_stream(unknown_stream_uuid)

    {:error, :stream_not_found} = Stream.read_stream_forward(stream, 0, 1)
  end

  describe "read stream forward" do
    setup [:append_events_to_stream]

    test "should fetch all events", context do
      {:ok, read_events} = Stream.read_stream_forward(context[:stream], 0, 1_000)

      assert length(read_events) == 3
    end
  end

  describe "subscribe to stream" do
    setup [:append_events_to_stream]

    test "from origin should receive all events", context do
      {:ok, _subscription} = Stream.subscribe_to_stream(context[:stream], @subscription_name, self, :origin)

      assert_receive {:events, received_events, _}
      assert length(received_events) == 3
    end

    test "from current should receive only new events", context do
      {:ok, _subscription} = Stream.subscribe_to_stream(context[:stream], @subscription_name, self, :current)

      refute_receive {:events, _received_events, _}

      events = EventFactory.create_events(1, 4)
      :ok = Stream.append_to_stream(context[:stream], 3, events)

      assert_receive {:events, received_events, _}
      assert length(received_events) == 1
    end

    test "from given stream version should receive only later events", context do
      {:ok, _subscription} = Stream.subscribe_to_stream(context[:stream], @subscription_name, self, 2)

      assert_receive {:events, received_events, _}
      assert length(received_events) == 1
    end
  end

  test "stream should correctly restore `stream_version` after reopening" do
    stream_uuid = UUID.uuid4
    events = EventFactory.create_events(3)

    {:ok, stream} = Streams.open_stream(stream_uuid)
    :ok = Stream.append_to_stream(stream, 0, events)

    # Stream above needed for preventing accidental event_id/stream_version match
    stream_uuid = UUID.uuid4
    events = EventFactory.create_events(3)

    {:ok, stream} = Streams.open_stream(stream_uuid)
    :ok = Stream.append_to_stream(stream, 0, events)
    {:ok, 3} = Stream.stream_version(stream)

    ProcessHelper.shutdown(stream)

    {:ok, stream} = Streams.open_stream(stream_uuid)
    {:ok, 3} = Stream.stream_version(stream)
  end

  defp append_events_to_stream(_context) do
    stream_uuid = UUID.uuid4
    events = EventFactory.create_events(3)

    {:ok, stream} = Streams.open_stream(stream_uuid)
    :ok = Stream.append_to_stream(stream, 0, events)

    [stream_uuid: stream_uuid, events: events, stream: stream]
  end
end
