defmodule EventStore.AppendToStreamTest do
  use EventStore.StorageCase

  alias EventStore.EventFactory

  describe "append to new stream using `:any_version`" do
    test "should persist events" do
      stream_uuid = UUID.uuid4()
      events = EventFactory.create_events(3)

      assert :ok = EventStore.append_to_stream(stream_uuid, :any_version, events)

      assert {:ok, events} = EventStore.read_stream_forward(stream_uuid)
      assert length(events) == 3
    end
  end

  describe "append to existing stream using `:any_version`" do
    setup [:append_events_to_stream]

    test "should persist events", %{stream_uuid: stream_uuid} do
      events = EventFactory.create_events(1)

      assert :ok = EventStore.append_to_stream(stream_uuid, :any_version, events)

      assert {:ok, events} = EventStore.read_stream_forward(stream_uuid)
      assert length(events) == 4
    end
  end

  describe "append to new stream using `:no_stream`" do
    test "should persist events" do
      stream_uuid = UUID.uuid4()
      events = EventFactory.create_events(3)

      assert :ok = EventStore.append_to_stream(stream_uuid, :no_stream, events)

      assert {:ok, events} = EventStore.read_stream_forward(stream_uuid)
      assert length(events) == 3
    end
  end

  describe "append to existing stream using `:no_stream`" do
    setup [:append_events_to_stream]

    test "should return `{:error, :stream_exists}`", %{stream_uuid: stream_uuid} do
      events = EventFactory.create_events(1)

      assert {:error, :stream_exists} = EventStore.append_to_stream(stream_uuid, :no_stream, events)
    end
  end

  describe "append to new stream using `:stream_exists`" do
    test "should return `{:error, :stream_does_not_exist}`" do
      stream_uuid = UUID.uuid4()
      events = EventFactory.create_events(3)

      assert {:error, :stream_does_not_exist} = EventStore.append_to_stream(stream_uuid, :stream_exists, events)
    end
  end

  describe "append to existing stream using `:stream_exists`" do
    setup [:append_events_to_stream]

    test "should persist events`", %{stream_uuid: stream_uuid} do
      events = EventFactory.create_events(1)

      assert :ok = EventStore.append_to_stream(stream_uuid, :stream_exists, events)

      assert {:ok, events} = EventStore.read_stream_forward(stream_uuid)
      assert length(events) == 4
    end
  end

  defp append_events_to_stream(_context) do
    stream_uuid = UUID.uuid4
    events = EventFactory.create_events(3)

    :ok = EventStore.append_to_stream(stream_uuid, 0, events)

    [stream_uuid: stream_uuid, events: events]
  end
end
