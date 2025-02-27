defmodule Commanded.Event.EventHandlerBatchSubscribeToStreamTest do
  use ExUnit.Case

  alias Commanded.{DefaultApp, EventStore}
  alias Commanded.Event.Mapper

  defmodule AnEvent do
    @derive Jason.Encoder
    defstruct [:stream_uuid, :reply_to]
  end

  defmodule SingleStreamBatchEventHandler do
    use Commanded.Event.Handler,
      application: DefaultApp,
      name: __MODULE__,
      subscribe_to: "stream2",
      batch_size: 3

    def handle_batch([{%AnEvent{stream_uuid: stream_uuid, reply_to: reply_to}, _metadata} | _rest]) do
      pid = :erlang.list_to_pid(reply_to)
      Process.send(pid, {:event, stream_uuid}, [])

      :ok
    end
  end

  describe "single stream batch event handler" do
    setup do
      start_supervised!(DefaultApp)
      start_supervised!(SingleStreamBatchEventHandler)

      :ok
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
    reply_to = :erlang.pid_to_list(self())

    events =
      1..count
      |> Enum.map(fn _i ->
        %AnEvent{reply_to: reply_to, stream_uuid: stream_uuid}
      end)
      |> Mapper.map_to_event_data()

    EventStore.append_to_stream(DefaultApp, stream_uuid, :any_version, events)
  end
end
