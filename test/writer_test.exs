defmodule EventStore.WriterTest do
  use EventStore.StorageCase
  doctest EventStore.Writer

  alias EventStore
  alias EventStore.{EventFactory,ProcessHelper}

  test "restart writer, should assign next event id on append to stream" do
    stream_uuid = UUID.uuid4
    events = EventFactory.create_events(2)

    :ok = EventStore.append_to_stream(stream_uuid, 0, [Enum.at(events, 0)])

    writer = Process.whereis(EventStore.Writer)
    ProcessHelper.shutdown(writer)

    :ok = EventStore.append_to_stream(stream_uuid, 1, [Enum.at(events, 1)])

    {:ok, events} = EventStore.read_stream_forward(stream_uuid)

    assert length(events) == 2
    assert Enum.map(events, &(&1.event_id)) == [1, 2]
  end
end
