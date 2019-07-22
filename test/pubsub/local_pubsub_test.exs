defmodule Commanded.PubSub.LocalPubSubTest do
  alias Commanded.PubSub.{LocalPubSub, PubSubTestCase}

  use PubSubTestCase, pubsub: LocalPubSub

  setup do
    child_spec = LocalPubSub.child_spec(LocalPubSub, [])

    for child <- child_spec, do: start_supervised!(child)

    :ok
  end
end
