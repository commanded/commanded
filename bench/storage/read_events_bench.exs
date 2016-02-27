defmodule ReadEventsBench do
  use Benchfella

  alias EventStore.EventFactory
  alias EventStore.Storage

  setup_all do
    Code.require_file("event_factory.ex", "test")
    Storage.start_link
  end

  before_each_bench(store) do
    events = EventFactory.create_events(100)
    stream_uuid = UUID.uuid4()

    {:ok, _} = EventStore.append_to_stream(store, stream_uuid, 0, events)

    {:ok, {store, stream_uuid}}
  end

  bench "read events, single reader" do
    {store, stream_uuid} = bench_context

    {:ok, _} = EventStore.read_stream_forward(store, stream_uuid, 0)
    :ok
  end
end
