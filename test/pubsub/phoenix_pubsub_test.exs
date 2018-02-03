defmodule Commanded.PubSub.PhoenixPubSubTest do
  use ExUnit.Case

  alias Commanded.PubSub.PhoenixPubSub
  alias Commanded.Helpers.ProcessHelper

  @topic "test"

  setup do
    Application.put_env(
      :commanded,
      :pubsub,
      phoenix_pubsub: [
        adapter: Phoenix.PubSub.PG2,
        pool_size: 1
      ]
    )

    children = PhoenixPubSub.child_spec()

    {:ok, pid} = Supervisor.start_link(children, strategy: :one_for_one)

    on_exit(fn ->
      Application.delete_env(:commanded, :pubsub)

      ProcessHelper.shutdown(pid)
    end)
  end

  describe "pub/sub" do
    test "should receive broadcast message" do
      assert :ok = PhoenixPubSub.subscribe(@topic)
      assert :ok = PhoenixPubSub.broadcast(@topic, :message)

      assert_receive(:message)
    end
  end

  describe "tracker" do
    test "should list tracked processes" do
      self = self()

      assert :ok = PhoenixPubSub.track(@topic, :example)
      assert [{:example, ^self}] = PhoenixPubSub.list(@topic)
    end
  end
end
