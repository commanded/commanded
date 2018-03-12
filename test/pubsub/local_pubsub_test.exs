defmodule Commanded.PubSub.LocalPubSubTest do
  use ExUnit.Case

  alias Commanded.PubSub.LocalPubSub

  @topic "test"

  setup do
    Application.put_env(:commanded, :pubsub, :local)

    {:ok, _pid} = Supervisor.start_link(LocalPubSub.child_spec(), strategy: :one_for_one)

    on_exit(fn ->
      Application.delete_env(:commanded, :pubsub)
    end)
  end

  describe "pub/sub" do
    test "should receive broadcast message" do
      assert :ok = LocalPubSub.subscribe(@topic)
      assert :ok = LocalPubSub.broadcast(@topic, :message)

      assert_receive(:message)
    end
  end

  describe "tracker" do
    test "should list tracked processes" do
      self = self()

      assert :ok = LocalPubSub.track(@topic, :example)
      assert [{:example, ^self}] = LocalPubSub.list(@topic)
    end
  end
end
