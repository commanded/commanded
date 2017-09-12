defmodule EventStore.Registration.DistributedRegistryTest do
  use EventStore.StorageCase

  alias EventStore.{Cluster,Streams}
  alias EventStore.Registration.DistributedRegistry

  @moduletag :distributed

  @node1 :"node1@127.0.0.1"
  @node2 :"node2@127.0.0.1"

  setup do
    on_exit fn ->
      Cluster.stop_nodes()
      Cluster.spawn_nodes()
    end
  end

  describe "cluster node down" do
    test "should redistribute stream processes on downed node to a running node" do
      stream_uuid = "stream1"
      {:ok, stream} = open_stream(@node1, stream_uuid)

      ref = Process.monitor(stream)

      # stop node hosting stream
      Cluster.stop_node(@node2)

      assert_receive {:DOWN, ^ref, _, _, _}

      :timer.sleep 2_000

      # ensure stream process is restarted on available node
      refute whereis_name(@node1, stream_uuid) == :undefined
      refute whereis_name(@node1, stream_uuid) == stream
    end
  end

  describe "cluster node down, then up" do
    test "should redistribute stream processes to rejoined node" do
      stream_uuid = "stream1"
      {:ok, stream} = open_stream(@node1, stream_uuid)

      ref = Process.monitor(stream)

      # stop node hosting stream
      Cluster.stop_node(@node2)

      assert_receive {:DOWN, ^ref, _, _, _}

      :timer.sleep 2_000

      # ensure stream process is restarted on available node
      stream = whereis_name(@node1, stream_uuid)
      refute stream == :undefined

      ref = Process.monitor(stream)

      # restart node2, stream should not be moved back onto node
      Cluster.spawn_node(@node2)

      # wait for node to start up
      :timer.sleep 2_000

      assert_receive {:DOWN, ^ref, _, _, _}

      assert whereis_name(@node1, stream_uuid) == :undefined
    end
  end

  defp open_stream(node, stream_uuid) do
    :rpc.call(node, Streams.Supervisor, :open_stream, [stream_uuid], :infinity)
  end

  defp whereis_name(node, name) do
    :rpc.call(node, DistributedRegistry, :whereis_name, [name], :infinity)
  end
end
