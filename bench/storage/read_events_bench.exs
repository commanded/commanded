defmodule ReadEventsBench do
  use Benchfella

  alias EventStore.EventFactory
  alias EventStore.Storage

  setup_all do
    Code.require_file("event_factory.ex", "test")
    Application.ensure_all_started(:eventstore)
  end

  before_each_bench(_) do
    events = EventFactory.create_events(100)
    stream_uuid = UUID.uuid4()

    {:ok, _} = EventStore.append_to_stream(stream_uuid, 0, events)

    {:ok, stream_uuid}
  end

  bench "read events, single reader" do
    stream_uuid = bench_context

    {:ok, _} = EventStore.read_stream_forward(stream_uuid)

    :ok
  end
end
