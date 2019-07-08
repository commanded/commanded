defmodule Commanded.PubSub.LocalPubSub do
  @moduledoc """
  Local pub/sub adapter, restricted to a single node, using Elixir's `Registry`.

  You can configure this adapter in your environment config file:

      # `config/config.exs`
      config :my_app, MyApp.Application, pubsub: :local

  This adapter will be used by default when none is specified in config.
  """

  @behaviour Commanded.PubSub

  @doc """
  Start a `Registry` for local pub/sub.
  """
  @impl Commanded.PubSub
  def child_spec(pubsub, _config) do
    local_pubsub_name = local_pubsub_name(pubsub)
    local_tracker_name = local_tracker_name(pubsub)

    [
      # Registry used for pub/sub
      {
        Registry,
        keys: :duplicate, name: local_pubsub_name, partitions: System.schedulers_online()
      },
      # Registry used for presence tracking
      {Registry, keys: :duplicate, name: local_tracker_name, partitions: 1}
    ]
  end

  @doc """
  Subscribes the caller to the topic.
  """
  @impl Commanded.PubSub
  def subscribe(pubsub, topic) when is_binary(topic) do
    name = local_pubsub_name(pubsub)

    {:ok, _} = Registry.register(name, topic, [])
    :ok
  end

  @doc """
  Broadcasts message on given topic.
  """
  @impl Commanded.PubSub
  def broadcast(pubsub, topic, message) when is_binary(topic) do
    name = local_pubsub_name(pubsub)

    Registry.dispatch(name, topic, fn entries ->
      for {pid, _} <- entries, do: send(pid, message)
    end)
  end

  @doc """
  Track the current process under the given `topic`, uniquely identified by
  `key`.
  """
  @impl Commanded.PubSub
  def track(pubsub, topic, key) when is_binary(topic) do
    name = local_tracker_name(pubsub)

    case Registry.match(name, topic, key) do
      [] ->
        {:ok, _pid} = Registry.register(name, topic, key)
        :ok

      _matches ->
        :ok
    end
  end

  @doc """
  List tracked terms and associated PIDs for a given topic.
  """
  @impl Commanded.PubSub
  def list(pubsub, topic) when is_binary(topic) do
    name = local_tracker_name(pubsub)

    Registry.lookup(name, topic) |> Enum.map(fn {pid, key} -> {key, pid} end)
  end

  defp local_pubsub_name(pubsub), do: Module.concat([pubsub, LocalPubSub])
  defp local_tracker_name(pubsub), do: Module.concat([pubsub, LocalPubSub.Tracker])
end
