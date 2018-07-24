defmodule Commanded.PubSub.PubSubTestCase do
  import Commanded.SharedTestCase

  define_tests do
    describe "pub/sub" do
      test "should receive broadcast message", %{pubsub: pubsub} do
        :ok = pubsub.subscribe("test")
        :ok = pubsub.broadcast("test", :message)

        assert_receive(:message)
        refute_receive(:message)
      end
    end

    describe "tracker" do
      test "should list tracked processes", %{pubsub: pubsub} do
        self = self()

        :ok = pubsub.track("test", :example1)
        :ok = pubsub.track("test", :example2)

        assert [{:example1, ^self}, {:example2, ^self}] = pubsub.list("test")
      end

      test "should ignore duplicate tracks", %{pubsub: pubsub} do
        self = self()

        :ok = pubsub.track("test", :example)
        :ok = pubsub.track("test", :example)
        :ok = pubsub.track("test", :example)

        assert [{:example, ^self}] = pubsub.list("test")
      end
    end
  end
end
