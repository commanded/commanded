defmodule Commanded.PubSub.LocalPubSubTest do
  use ExUnit.Case

  alias Commanded.PubSub.LocalRegistry

  describe "pub/sub" do
    test "should receive broadcast message" do
      assert :ok = LocalRegistry.subscribe(:test)
      assert :ok = LocalRegistry.broadcast(:test, :message)

      assert_receive(:message)
    end
  end

  describe "tracker" do
    test "should list tracked processes" do
      self = self()

      assert :ok = LocalRegistry.track(:test, :example)
      assert [{:example, ^self}] = LocalRegistry.list(:test)
    end
  end
end
