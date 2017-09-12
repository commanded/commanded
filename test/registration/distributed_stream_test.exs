defmodule EventStore.Registration.DistributedStreamTest do
  use EventStore.StorageCase

  @moduletag :distributed

  describe "swarm callbacks" do
    setup [:open_stream]

    test "should handle swarm :begin_handof call", %{stream: stream} do
      assert :ignore = GenServer.call(stream, {:swarm, :begin_handoff})
    end

    test "should handle swarm :die info", %{stream: stream} do
      ref = Process.monitor(stream)
      Process.unlink(stream)

      send(stream, {:swarm, :die})

      assert_receive {:DOWN, ^ref, _, _, _}
    end
  end

  def open_stream(_context) do
    stream_uuid = UUID.uuid4()

    {:ok, stream} = EventStore.Streams.Supervisor.open_stream(stream_uuid)

    [stream: stream]
  end
end
