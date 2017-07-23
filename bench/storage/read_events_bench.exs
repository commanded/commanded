defmodule ReadEventsBench do
  use Benchfella

  alias EventStore.EventFactory

  @await_timeout_ms 100_000

  setup_all do
    EventStore.StorageInitializer.reset_storage!()

    stream_uuid = UUID.uuid4()
    events = EventFactory.create_events(100)

    :ok = EventStore.append_to_stream(stream_uuid, 0, events)

    {:ok, stream_uuid}
  end

  bench "read events, single reader" do
    {:ok, _} = EventStore.read_stream_forward(bench_context)

    :ok
  end

  bench "read events, 10 concurrent readers" do
    read_stream_forward(bench_context, 10)
  end

  bench "read events, 100 concurrent readers" do
    read_stream_forward(bench_context, 100)
  end

  defp read_stream_forward(stream_uuid, concurrency) do
    tasks = Enum.map 1..concurrency, fn (_) ->
      Task.async fn ->
        {:ok, _} = EventStore.read_stream_forward(stream_uuid)
      end
    end

    Enum.each(tasks, &Task.await(&1, @await_timeout_ms))
  end
end
