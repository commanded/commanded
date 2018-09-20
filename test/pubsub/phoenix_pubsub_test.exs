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

    pubsub_pid =
      case Process.whereis(PhoenixPubSub) do
        nil ->
          {:ok, pid} = Supervisor.start_link(PhoenixPubSub.child_spec(), strategy: :one_for_one)
          pid

        pid ->
          pid
      end

    on_exit(fn ->
      Application.delete_env(:commanded, :pubsub)
    end)

    [pubsub_pid: pubsub_pid]
  end
end
