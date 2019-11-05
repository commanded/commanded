defmodule Commanded.PubSub.PhoenixPubSubTest do
  alias Commanded.PubSub.{PhoenixPubSub, PubSubTestCase}

  use PubSubTestCase, pubsub: PhoenixPubSub

  setup do
    config = [adapter: Phoenix.PubSub.PG2, pool_size: 1]
    {:ok, child_spec, pubsub_meta} = PhoenixPubSub.child_spec(PhoenixPubSub, config)

    for child <- child_spec, do: start_supervised!(child)

    [pubsub_meta: pubsub_meta]
  end
end
