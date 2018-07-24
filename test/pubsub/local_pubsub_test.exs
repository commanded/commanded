defmodule Commanded.PubSub.LocalPubSubTest do
  alias Commanded.PubSub.{LocalPubSub, PubSubTestCase}

  use PubSubTestCase, pubsub: LocalPubSub

  setup do
    Application.put_env(:commanded, :pubsub, :local)

    if Process.whereis(Commanded.PubSub.LocalPubSub) == nil do
      {:ok, _pid} = Supervisor.start_link(LocalPubSub.child_spec(), strategy: :one_for_one)
    end

    on_exit(fn ->
      Application.delete_env(:commanded, :pubsub)
    end)
  end
end
