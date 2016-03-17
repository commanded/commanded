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

  bench "append events, 10 concurrent writers" do
    events = bench_context

    append_events(events, 10)

    :ok
  end

  bench "append events, 100 concurrent writers" do
    events = bench_context

    append_events(events, 100)

    :ok
  end

  defp append_events(events, concurrency) do
    await_timeout_ms = 100_000

    tasks = Enum.map 1..concurrency, fn (_) ->
      stream_uuid = UUID.uuid4()

      Task.async fn ->
        {:ok, _} = EventStore.append_to_stream(stream_uuid, 0, events)
      end
    end

    Enum.each(tasks, &Task.await(&1, await_timeout_ms))
  end
end
