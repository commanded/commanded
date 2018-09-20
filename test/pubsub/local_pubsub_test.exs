defmodule Commanded.PubSub.LocalPubSubTest do
  alias Commanded.PubSub.{LocalPubSub, PubSubTestCase}

  use PubSubTestCase, pubsub: LocalPubSub

  setup do
    Application.put_env(:commanded, :pubsub, :local)

    pubsub_pid =
      case Process.whereis(LocalPubSub) do
        nil ->
          {:ok, pid} = Supervisor.start_link(LocalPubSub.child_spec(), strategy: :one_for_one)
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
