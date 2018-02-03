defmodule Commanded.PubSub.LocalPubSub do
  @moduledoc """
  Local pub/sub adapter, restricted to a single node, using Elixir's
  [Registry](https://hexdocs.pm/elixir/Registry.html) module.

  You can configure this adapter in your environment config file:

      # `config/config.exs`
      config :commanded, pubsub: :local

  This adapter will be used by default when none is specified in config.
  """

  @behaviour Commanded.PubSub

  alias Commanded.PubSub.LocalPubSub

  @doc """
  Start a `Registry` for local pub/sub.
  """
  @spec child_spec() :: [:supervisor.child_spec()]
  @impl Commanded.PubSub
  def child_spec do
    [
      # registry used for pub/sub
      {
        Registry,
        keys: :duplicate, name: LocalPubSub, partitions: System.schedulers_online()
      },
      # registry used for presence tracking
      {Registry, keys: :duplicate, name: LocalPubSub.Tracker, partitions: 1}
    ]
  end

  @doc """
  Subscribes the caller to the topic.
  """
  @spec subscribe(String.t()) :: :ok | {:error, term}
  @impl Commanded.PubSub
  def subscribe(topic) when is_binary(topic) do
    {:ok, _} = Registry.register(LocalPubSub, topic, [])
    :ok
  end

  @doc """
  Broadcasts message on given topic.
  """
  @spec broadcast(String.t(), term) :: :ok | {:error, term}
  @impl Commanded.PubSub
  def broadcast(topic, message) when is_binary(topic) do
    Registry.dispatch(LocalPubSub, topic, fn entries ->
      for {pid, _} <- entries, do: send(pid, message)
    end)
  end

  @doc """
  Track the current process under the given `topic`, uniquely identified by
  `key`.
  """
  @spec track(String.t(), term) :: :ok
  @impl Commanded.PubSub
  def track(topic, key) when is_binary(topic) do
    {:ok, _} = Registry.register(LocalPubSub.Tracker, topic, key)

    :ok
  end

  @doc """
  List tracked terms and associated PIDs for a given topic.
  """
  @spec list(String.t()) :: [{term, pid}]
  @impl Commanded.PubSub
  def list(topic) when is_binary(topic) do
    Registry.match(LocalPubSub.Tracker, topic, :_) |> Enum.map(fn {pid, key} -> {key, pid} end)
  end
end
