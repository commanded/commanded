defmodule AppendEventsBench do
  use Benchfella

  alias EventStore.EventFactory
  alias EventStore.Storage

  setup_all do
    Code.require_file("event_factory.ex", "test")
    Application.ensure_all_started(:eventstore)
  end

  before_each_bench(store) do
    {:ok, EventFactory.create_events(100)}
  end

  bench "append events, single writer" do
    {:ok, _} = EventStore.append_to_stream(UUID.uuid4, 0, bench_context)
    :ok
  end

  bench "append events, 10 concurrent writers" do
    append_events(bench_context, 10)
    :ok
  end

  bench "append events, 100 concurrent writers" do
    append_events(bench_context, 100)
    :ok
  end

  defp append_events(events, concurrency) do
    await_timeout_ms = 100_000

    tasks = Enum.map 1..concurrency, fn (_) ->
      stream_uuid = UUID.uuid4

      Task.async fn ->
        {:ok, _} = EventStore.append_to_stream(stream_uuid, 0, events)
      end
    end

    Enum.each(tasks, &Task.await(&1, await_timeout_ms))
  end
end
