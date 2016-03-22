defmodule EventStore.Publishing.PublishEventsTest do
  use EventStore.StorageCase
  doctest EventStore.Publisher

  alias EventStore.{EventFactory,Publisher,Storage,Subscriptions,Subscriber}

  @all_stream "$all"
  @subscription_name "test_subscription"

  test "should publish events ordered by event id" do
    stream1_uuid = UUID.uuid4()
    stream2_uuid = UUID.uuid4()
    stream1_events = EventFactory.create_events(1)
    stream2_events = EventFactory.create_events(1)

    {:ok, subscriber} = Subscriber.start_link(self)
    {:ok, _} = Subscriptions.subscribe_to_stream(@all_stream, @subscription_name, subscriber)

    {:ok, stream1_persisted_events} = Storage.append_to_stream(stream1_uuid, 0, stream1_events)
    {:ok, stream2_persisted_events} = Storage.append_to_stream(stream2_uuid, 0, stream2_events)

    # notify stream2 events before stream1 (out of order)
    Publisher.notify_events(stream2_uuid, stream2_persisted_events)
    Publisher.notify_events(stream1_uuid, stream1_persisted_events)

    # should receive events in correct order (by event_id)
    assert_receive {:events, stream1_received_events}
    assert_receive {:events, stream2_received_events}

    assert stream1_received_events == stream1_persisted_events
    assert stream2_received_events == stream2_persisted_events

    assert Subscriber.received_events(subscriber) == stream1_persisted_events ++ stream2_persisted_events
  end
end
