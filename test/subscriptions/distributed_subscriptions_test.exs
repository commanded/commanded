defmodule Commanded.DistributedSubscriptionsTest do
  use ExUnit.Case

  alias Commanded.Subscriptions.DistributedSubscribers

  @moduletag :distributed

  setup do
    {"", 0} = System.cmd("epmd", ["-daemon"])
    :ok = LocalCluster.start()

    # Peers also start Mox, which registers `{:global, Mox.Server}`. When two
    # nodes register the same global name, `:global` keeps the process on the
    # node whose name sorts first and kills the other. The prefix must sort
    # after the test node ("manager") so the test node's Mox.Server survives.
    {:ok, cluster} =
      LocalCluster.start_link(3,
        prefix: "peer",
        applications: [:commanded]
      )

    {:ok, nodes} = LocalCluster.nodes(cluster)

    [nodes: nodes]
  end

  describe "distributed subscriptions" do
    test "should be registered on all nodes", %{nodes: nodes} do
      DistributedSubscribers.start_subscribers(nodes)
      DistributedSubscribers.query_subscriptions(nodes)

      expected_subscribers = DistributedSubscribers.all() |> Enum.map(&inspect/1) |> Enum.sort()

      for node <- nodes do
        assert_receive {:subscriptions, ^node, ^expected_subscribers}
      end
    end
  end
end
