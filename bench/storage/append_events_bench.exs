defmodule AppendEventsBench do
  use Benchfella

  alias EventStore.EventFactory
  alias EventStore.Storage

  setup_all do
    Code.require_file("event_factory.ex", "test")
    Application.ensure_all_started(:eventstore)
  end

  before_each_bench(store) do
    events = EventFactory.create_events(100)
    {:ok, events}
  end

  bench "append events, single writer" do
    events = bench_context

    stream_uuid = UUID.uuid4()

    {:ok, _} = EventStore.append_to_stream(stream_uuid, 0, events)

    :ok
  end
end
