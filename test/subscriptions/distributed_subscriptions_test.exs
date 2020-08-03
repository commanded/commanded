defmodule Commanded.DistributedSubscriptionsTest do
  use ExUnit.Case

  alias Commanded.Subscriptions.DistributedSubscribers

  @moduletag :distributed

  setup do
    :ok = LocalCluster.start()

    nodes = LocalCluster.start_nodes("commanded", 3)

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
