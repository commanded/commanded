defmodule EventStore.Streams.StreamTest do
  use EventStore.StorageCase
  doctest EventStore.Streams.Supervisor
  doctest EventStore.Streams.Stream

  alias EventStore.EventFactory
  alias EventStore.ProcessHelper
  alias EventStore.Streams
  alias EventStore.Streams.Stream

  @all_stream "$all"

  @tag :wip
  test "open a stream" do
    stream_uuid = UUID.uuid4()

    {:ok, stream} = Streams.open_stream(stream_uuid)

    assert stream != nil
  end

  test "open single stream twice" do
    stream_uuid = UUID.uuid4()

    {:ok, stream1} = Streams.open_stream(stream_uuid)
    {:ok, stream2} = Streams.open_stream(stream_uuid)

    assert stream1 != nil
    assert stream2 != nil
    assert stream1 == stream2
  end

  test "stream crash should allow starting new stream process" do
    stream_uuid = UUID.uuid4()

    {:ok, stream} = Streams.open_stream(stream_uuid)

    ProcessHelper.shutdown(stream)

    {:ok, stream} = Streams.open_stream(stream_uuid)
    assert stream != nil
  end

  test "append events to stream" do
    stream_uuid = UUID.uuid4()
    events = EventFactory.create_events(3)

    {:ok, stream} = Streams.open_stream(stream_uuid)
    {:ok, persisted_events} = Stream.append_to_stream(stream, 0, events)

    assert length(persisted_events) == 3
  end
end
