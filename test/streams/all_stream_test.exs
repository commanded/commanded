defmodule EventStore.Streams.AllStreamTest do
  use EventStore.StorageCase
  doctest EventStore.Streams.Supervisor
  doctest EventStore.Streams.Stream

  alias EventStore.EventFactory
  alias EventStore.Streams
  alias EventStore.Streams.{AllStream,Stream}

  @subscription_name "test_subscription"

  describe "read stream forward" do
    setup [:append_events_to_streams]

    test "should fetch events from all streams" do
      {:ok, read_events} = AllStream.read_stream_forward(0, 1_000)

      assert length(read_events) == 6
    end
  end

  describe "subscribe to all streams" do
    setup [:append_events_to_streams]

    test "from origin should receive all events" do
      {:ok, _subscription} = AllStream.subscribe_to_stream(@subscription_name, self, :origin)

      assert_receive {:events, received_events1, _}
      assert_receive {:events, received_events2, _}
      assert length(received_events1 ++ received_events2) == 6
    end

    test "from current should receive only new events", context do
      {:ok, _subscription} = AllStream.subscribe_to_stream(@subscription_name, self, :current)

      refute_receive {:events, _received_events, _}

      events = EventFactory.create_events(1, 4)
      :ok = Stream.append_to_stream(context[:stream1], 3, events)

      assert_receive {:events, received_events, _}
      assert length(received_events) == 1
    end

    test "from given event id should receive only later events" do
      {:ok, _subscription} = AllStream.subscribe_to_stream(@subscription_name, self, 2)

      assert_receive {:events, received_events1, _}
      assert_receive {:events, received_events2, _}
      assert length(received_events1 ++ received_events2) == 4
    end
  end

  defp append_events_to_streams(_context) do
    {stream1_uuid, stream1, stream1_events} = append_events_to_stream
    {stream2_uuid, stream2, stream2_events} = append_events_to_stream

    [
      stream1_uuid: stream1_uuid,
      stream1: stream1,
      stream1_events: stream1_events,
      stream2_uuid: stream2_uuid,
      stream2: stream2,
      stream2_events: stream2_events,
    ]
  end

  defp append_events_to_stream do
    stream_uuid = UUID.uuid4
    events = EventFactory.create_events(3)

    {:ok, stream} = Streams.open_stream(stream_uuid)
    :ok = Stream.append_to_stream(stream, 0, events)

    {stream_uuid, stream, events}
  end
end
