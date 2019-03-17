defmodule Event.UpcasterTest do
  use Commanded.StorageCase

  alias Commanded.EventStore
  alias Commanded.EventStore.EventData
  alias Commanded.Event.Upcast.Events.{EventOne, EventTwo, EventThree, EventFour, Stop}

  describe "event store stream forward" do
    setup do
      %{
        stream_uuid: UUID.uuid4(:hex)
      }
    end

    test "will not upcast an event without an upcaster", %{stream_uuid: stream_uuid} do
      %{data: %{n: n}} =
        stream_uuid
        |> write_events(struct(EventOne, n: 0))
        |> read_event()

      assert n == 0
    end

    test "will upcast using defined upcaster", %{stream_uuid: stream_uuid} do
      %{data: %{n: n}} =
        stream_uuid
        |> write_events(struct(EventTwo, n: 10))
        |> read_event()

      assert n == 20
    end

    test "can adapt new event from old event", %{stream_uuid: stream_uuid} do
      %{data: %EventFour{name: name}} =
        stream_uuid
        |> write_events(struct(EventThree, n: 0))
        |> read_event()

      assert name == "Chris"
    end
  end

  describe "event handler" do
    alias Commanded.Event.Upcast.EventHandler

    setup do
      {:ok, handler} = EventHandler.start_link()

      %{
        stream_uuid: UUID.uuid4(:hex),
        handler: handler,
        reply_to: :erlang.pid_to_list(self())
      }
    end

    test "will receive upcasted events", %{stream_uuid: stream_uuid, reply_to: reply_to} do
      stream_uuid
      |> write_events([
        struct(EventOne, n: 0, reply_to: reply_to),
        struct(EventTwo, n: 10, reply_to: reply_to),
        struct(EventThree, n: 0, reply_to: reply_to)
      ])

      refute_receive %EventThree{}

      assert_receive %EventOne{n: 0}
      assert_receive %EventTwo{n: 20}
      assert_receive %EventFour{name: "Chris"}
    end
  end

  describe "process manager" do
    alias Commanded.Event.Upcast.ProcessManager

    setup do
      {:ok, manager} = ProcessManager.start_link()

      %{
        stream_uuid: UUID.uuid4(:hex),
        manager: manager,
        reply_to: :erlang.pid_to_list(self()),
        process_id: UUID.uuid4(:hex)
      }
    end

    test "will receive upcasted events", context do
      %{stream_uuid: stream_uuid, reply_to: reply_to, process_id: process_id} = context

      stream_uuid
      |> write_events([
        struct(EventOne, n: 0, reply_to: reply_to, process_id: process_id),
        struct(EventTwo, n: 10, reply_to: reply_to, process_id: process_id),
        struct(EventThree, n: 0, reply_to: reply_to, process_id: process_id),
        struct(Stop, process_id: process_id)
      ])

      refute_receive %EventThree{}

      assert_receive %EventOne{n: 0}
      assert_receive %EventTwo{n: 20}
      assert_receive %EventFour{name: "Chris"}
    end
  end

  defp write_events(stream_uuid, events) do
    EventStore.append_to_stream(
      stream_uuid,
      :any_version,
      events |> List.wrap() |> Enum.map(&create_event/1)
    )

    stream_uuid
  end

  defp create_event(%{__struct__: event_type} = data) do
    %EventData{
      event_type: to_string(event_type),
      data: data,
      metadata: %{}
    }
  end

  defp read_event(stream_uuid) do
    EventStore.stream_forward(stream_uuid)
    |> Enum.into([])
    |> hd()
  end
end
