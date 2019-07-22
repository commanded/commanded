defmodule Commanded.PubSub.PhoenixPubSubTest do
  alias Commanded.PubSub.{PhoenixPubSub, PubSubTestCase}

  use PubSubTestCase, pubsub: PhoenixPubSub

  setup do
    config = [adapter: Phoenix.PubSub.PG2, pool_size: 1]
    child_spec = PhoenixPubSub.child_spec(PhoenixPubSub, config)

    for child <- child_spec, do: start_supervised!(child)

    :ok
  end
end
