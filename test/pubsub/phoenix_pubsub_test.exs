defmodule Commanded.PubSub.PhoenixPubSubTest do
  alias Commanded.PubSub.{PhoenixPubSub, PubSubTestCase}

  use PubSubTestCase, pubsub: PhoenixPubSub

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
end
