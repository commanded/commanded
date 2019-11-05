defmodule Commanded.PubSub.LocalPubSub do
  @moduledoc """
  Local pub/sub adapter, restricted to a single node, using Elixir's `Registry`.

  You can configure this adapter in your environment config file:

      # `config/config.exs`
      config :my_app, MyApp.Application, pubsub: :local

  This adapter will be used by default when none is specified in config.
  """

  @behaviour Commanded.PubSub.Adapter

  @doc """
  Start a `Registry` for local pub/sub.
  """
  @impl Commanded.PubSub.Adapter
  def child_spec(application, _config) do
    local_pubsub_name = Module.concat([application, LocalPubSub])
    local_tracker_name = Module.concat([application, LocalPubSub.Tracker])

    child_spec = [
      # Registry used for local pub/sub
      {
        Registry,
        keys: :duplicate, name: local_pubsub_name, partitions: System.schedulers_online()
      },
      # Registry used for process presence tracking
      {Registry, keys: :duplicate, name: local_tracker_name, partitions: 1}
    ]

    {:ok, child_spec, %{pubsub_name: local_pubsub_name, tracker_name: local_tracker_name}}
  end

  @doc """
  Subscribes the caller to the topic.
  """
  @impl Commanded.PubSub.Adapter
  def subscribe(adapter_meta, topic) when is_binary(topic) do
    name = local_pubsub_name(adapter_meta)

    {:ok, _} = Registry.register(name, topic, [])

    :ok
  end

  @doc """
  Broadcasts message on given topic.
  """
  @impl Commanded.PubSub.Adapter
  def broadcast(adapter_meta, topic, message) when is_binary(topic) do
    name = local_pubsub_name(adapter_meta)

    Registry.dispatch(name, topic, fn entries ->
      for {pid, _} <- entries, do: send(pid, message)
    end)
  end

  @doc """
  Track the current process under the given `topic`, uniquely identified by
  `key`.
  """
  @impl Commanded.PubSub.Adapter
  def track(adapter_meta, topic, key) when is_binary(topic) do
    name = local_tracker_name(adapter_meta)

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
  @impl Commanded.PubSub.Adapter
  def list(adapter_meta, topic) when is_binary(topic) do
    name = local_tracker_name(adapter_meta)

    Registry.lookup(name, topic) |> Enum.map(fn {pid, key} -> {key, pid} end)
  end

  defp local_pubsub_name(adapter_meta), do: Map.get(adapter_meta, :pubsub_name)
  defp local_tracker_name(adapter_meta), do: Map.get(adapter_meta, :tracker_name)
end
