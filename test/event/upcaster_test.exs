defmodule Event.UpcasterTest do
  use ExUnit.Case

  alias Commanded.Aggregates.Aggregate
  alias Commanded.DefaultApp
  alias Commanded.EventStore
  alias Commanded.EventStore.EventData
  alias Commanded.EventStore.RecordedEvent
  alias Commanded.Event.Upcast.Events.{EventOne, EventTwo, EventThree, EventFour, Stop}
  alias Commanded.Event.Upcast.UpcastAggregate

  setup do
    start_supervised!(DefaultApp)

    :ok
  end

  describe "upcast events from event store stream forward" do
    test "will not upcast an event without an upcaster" do
      assert %EventOne{version: version} =
               write_events(DefaultApp, struct(EventOne, version: 1)) |> read_event()

      assert version == 1
    end

    test "will upcast using defined upcaster" do
      assert %EventTwo{version: version} =
               write_events(DefaultApp, struct(EventTwo, version: 1)) |> read_event()

      assert version == 2
    end

    test "can adapt new event from old event" do
      assert %EventFour{name: name, version: version} =
               write_events(DefaultApp, struct(EventThree, version: 1)) |> read_event()

      assert name == "Chris"
      assert version == 2
    end
  end

  describe "upcast events received by aggregate" do
    test "should receive upcasted events" do
      {:ok, pid} =
        Aggregate.start_link([application: DefaultApp],
          aggregate_module: UpcastAggregate,
          aggregate_uuid: "upcast"
        )

      event = %RecordedEvent{
        event_id: UUID.uuid4(),
        event_number: 1,
        stream_id: "upcast",
        stream_version: 1,
        data: %EventThree{version: 1, reply_to: :erlang.pid_to_list(self())},
        metadata: %{}
      }

      # Send event which needs to be upcast
      send(pid, {:events, [event]})

      assert_receive %EventFour{version: 2, name: "Chris"}
    end
  end

  describe "upcast events received by event handler" do
    alias Commanded.Event.Upcast.EventHandler

    setup do
      handler = start_supervised!(EventHandler)

      [
        handler: handler,
        reply_to: :erlang.pid_to_list(self())
      ]
    end

    test "will receive upcasted events", %{reply_to: reply_to} do
      write_events(
        DefaultApp,
        [
          struct(EventOne, version: 1, reply_to: reply_to),
          struct(EventTwo, version: 1, reply_to: reply_to),
          struct(EventThree, version: 1, reply_to: reply_to)
        ]
      )

      assert_receive %EventOne{version: 1}
      assert_receive %EventTwo{version: 2}
      assert_receive %EventFour{version: 2, name: "Chris"}
      refute_receive %EventThree{}
    end
  end

  describe "upcast events received by process manager" do
    alias Commanded.Event.Upcast.ProcessManager
    alias Commanded.Event.Upcast.ProcessManager.Application

    setup do
      start_supervised!(Application)
      start_supervised!(ProcessManager)

      :ok
    end

    test "will receive upcasted events" do
      process_id = UUID.uuid4(:hex)
      reply_to = :erlang.pid_to_list(self())

      write_events(Application, [
        struct(EventOne, version: 1, reply_to: reply_to, process_id: process_id),
        struct(EventTwo, version: 1, reply_to: reply_to, process_id: process_id),
        struct(EventThree, version: 1, reply_to: reply_to, process_id: process_id),
        struct(Stop, process_id: process_id)
      ])

      refute_receive %EventThree{}

      assert_receive %EventOne{version: 1}
      assert_receive %EventTwo{version: 2}
      assert_receive %EventFour{version: 2, name: "Chris"}
    end
  end

  defp write_events(application, events) do
    stream_uuid = UUID.uuid4()
    events = events |> List.wrap() |> Enum.map(&create_event/1)

    :ok = EventStore.append_to_stream(application, stream_uuid, :any_version, events)

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
    EventStore.stream_forward(DefaultApp, stream_uuid)
    |> Enum.at(0)
    |> Map.get(:data)
  end
end
