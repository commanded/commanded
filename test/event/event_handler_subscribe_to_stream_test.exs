defmodule Commanded.Event.EventHandlerSubscribeToStreamTest do
  use Commanded.StorageCase

  alias Commanded.EventStore

  defmodule AnEvent do
    defstruct [:stream_uuid, :reply_to]
  end

  defmodule SingleStreamEventHandler do
    use Commanded.Event.Handler, name: __MODULE__, subscribe_to: "stream2"

    def handle(%AnEvent{} = event, _metadata) do
      %AnEvent{stream_uuid: stream_uuid, reply_to: reply_to} = event

      pid = :erlang.list_to_pid(reply_to)

      Process.send(pid, {:event, stream_uuid}, [])
    end
  end

  describe "single stream event handler" do
    setup do
      {:ok, handler} = SingleStreamEventHandler.start_link()

      [handler: handler]
    end

    test "should be only be notified of events appended to subscribed stream" do
      append_events_to_stream("stream1", 3)
      append_events_to_stream("stream2", 3)
      append_events_to_stream("stream3", 3)

      assert_receive {:event, "stream2"}
      assert_receive {:event, "stream2"}
      assert_receive {:event, "stream2"}
      refute_receive {:event, _stream_uuid}
    end
  end

  defp append_events_to_stream(stream_uuid, count) do
    reply_to = self() |> :erlang.pid_to_list()

    events =
      1..count
      |> Enum.map(fn _i ->
        %AnEvent{reply_to: reply_to, stream_uuid: stream_uuid}
      end)
      |> Commanded.Event.Mapper.map_to_event_data([])

    EventStore.append_to_stream(stream_uuid, :any_version, events)
  end
end
