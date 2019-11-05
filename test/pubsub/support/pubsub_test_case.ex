defmodule Commanded.PubSub.PubSubTestCase do
  import Commanded.SharedTestCase

  define_tests do
    describe "pub/sub" do
      test "should receive broadcast message", %{pubsub: pubsub, pubsub_meta: pubsub_meta} do
        :ok = pubsub.subscribe(pubsub_meta, "topic")
        :ok = pubsub.broadcast(pubsub_meta, "topic", :message)

        assert_receive(:message)
        refute_receive(:message)
      end
    end

    describe "tracker" do
      test "should list tracked processes", %{pubsub: pubsub, pubsub_meta: pubsub_meta} do
        self = self()

        :ok = pubsub.track(pubsub_meta, "topic", :key1)
        :ok = pubsub.track(pubsub_meta, "topic", :key2)

        assert [{:key1, ^self}, {:key2, ^self}] = pubsub.list(pubsub_meta, "topic")
      end

      test "should ignore duplicate tracks for existing process", %{
        pubsub: pubsub,
        pubsub_meta: pubsub_meta
      } do
        self = self()

        :ok = pubsub.track(pubsub_meta, "topic", :key)
        :ok = pubsub.track(pubsub_meta, "topic", :key)
        :ok = pubsub.track(pubsub_meta, "topic", :key)

        assert [{:key, ^self}] = pubsub.list(pubsub_meta, "topic")
      end
    end
  end
end
