defmodule Commanded.PubSub.PubSubTestCase do
  import Commanded.SharedTestCase

  define_tests do
    describe "pub/sub" do
      test "should receive broadcast message", %{pubsub: pubsub} do
        :ok = pubsub.subscribe(pubsub, "topic")
        :ok = pubsub.broadcast(pubsub, "topic", :message)

        assert_receive(:message)
        refute_receive(:message)
      end
    end

    describe "tracker" do
      test "should list tracked processes", %{pubsub: pubsub} do
        self = self()

        :ok = pubsub.track(pubsub, "topic", :key1)
        :ok = pubsub.track(pubsub, "topic", :key2)

        assert [{:key1, ^self}, {:key2, ^self}] = pubsub.list(pubsub, "topic")
      end

      test "should ignore duplicate tracks for existing process", %{pubsub: pubsub} do
        self = self()

        :ok = pubsub.track(pubsub, "topic", :key)
        :ok = pubsub.track(pubsub, "topic", :key)
        :ok = pubsub.track(pubsub, "topic", :key)

        assert [{:key, ^self}] = pubsub.list(pubsub, "topic")
      end
    end
  end
end
