defmodule Commanded.PubSub.PhoenixPubSubTest do
  use ExUnit.Case

  alias Commanded.PubSub.PhoenixPubSub

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

    {:ok, _pid} = Supervisor.start_link(PhoenixPubSub.child_spec(), strategy: :one_for_one)

    on_exit(fn ->
      Application.delete_env(:commanded, :pubsub)
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
