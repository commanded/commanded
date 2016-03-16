defmodule EventStore.Streams.StreamTest do
  use ExUnit.Case
  doctest EventStore.Streams.Supervisor
  doctest EventStore.Streams.Stream

  alias EventStore.EventFactory
  alias EventStore.ProcessHelper
  alias EventStore.Storage
  alias EventStore.Streams
  alias EventStore.Streams.Stream

  @all_stream "$all"

  setup do
    {:ok, storage} = Storage.start_link
    :ok = Storage.reset!(storage)
    {:ok, streams} = Streams.start_link(storage)
    {:ok, storage: storage, streams: streams}
  end

  test "open a stream", %{streams: streams} do
    stream_uuid = UUID.uuid4()

    {:ok, stream} = Streams.open_stream(streams, stream_uuid)

    assert stream != nil
  end

  test "open single stream twice", %{streams: streams} do
    stream_uuid = UUID.uuid4()

    {:ok, stream1} = Streams.open_stream(streams, stream_uuid)
    {:ok, stream2} = Streams.open_stream(streams, stream_uuid)

    assert stream1 != nil
    assert stream2 != nil
    assert stream1 == stream2
  end

  test "stream crash should allow starting new stream process", %{streams: streams} do
    stream_uuid = UUID.uuid4()

    {:ok, stream} = Streams.open_stream(streams, stream_uuid)

    ProcessHelper.shutdown(stream)

    {:ok, stream} = Streams.open_stream(streams, stream_uuid)
    assert stream != nil
  end

  @tag :wip
  test "append events to stream", %{streams: streams} do
    stream_uuid = UUID.uuid4()
    events = EventFactory.create_events(3)

    {:ok, stream} = Streams.open_stream(streams, stream_uuid)
    {:ok, persisted_events} = Stream.append_to_stream(stream, 0, events)

    assert persisted_events == 3
  end
end
