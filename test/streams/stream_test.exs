defmodule EventStore.Streams.StreamTest do
  use EventStore.StorageCase
  doctest EventStore.Streams.Supervisor
  doctest EventStore.Streams.Stream

  alias EventStore.EventFactory
  alias EventStore.ProcessHelper
  alias EventStore.Streams
  alias EventStore.Streams.Stream

  @all_stream "$all"

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

  test "stream crash should allow starting new stream process" do
    stream_uuid = UUID.uuid4

    {:ok, stream} = Streams.open_stream(stream_uuid)

    ProcessHelper.shutdown(stream)

    {:ok, stream} = Streams.open_stream(stream_uuid)
    assert stream != nil
  end

  test "append events to stream" do
    stream_uuid = UUID.uuid4
    events = EventFactory.create_events(3)

    {:ok, stream} = Streams.open_stream(stream_uuid)
    :ok = Stream.append_to_stream(stream, 0, events)
  end

  test "attempt to append events for wrong expected version should error" do
    stream_uuid = UUID.uuid4
    events = EventFactory.create_events(3)

    {:ok, stream} = Streams.open_stream(stream_uuid)
    :ok = Stream.append_to_stream(stream, 0, events)

    {:error, :wrong_expected_version} = Stream.append_to_stream(stream, 0, events)
  end

  test "attempt to read an unknown stream forward should error" do
    stream_uuid = UUID.uuid4
    {:ok, stream} = Streams.open_stream(stream_uuid)

    {:error, :stream_not_found} = Stream.read_stream_forward(stream)
  end

  test "read stream forward" do
    stream_uuid = UUID.uuid4
    events = EventFactory.create_events(3)

    {:ok, stream} = Streams.open_stream(stream_uuid)
    :ok = Stream.append_to_stream(stream, 0, events)

    {:ok, read_events} = Stream.read_stream_forward(stream)
    assert length(read_events) == 3
  end

  test "stream should correctly restore stream_version after reopening" do
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
end
