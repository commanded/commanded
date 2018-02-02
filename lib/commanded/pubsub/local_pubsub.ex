defmodule Commanded.PubSub.LocalRegistry do
  @moduledoc """
  Local pub/sub adapter, restricted to a single node, using Elixir's
  [Registry](https://hexdocs.pm/elixir/Registry.html) module.
  """

  @behaviour Commanded.PubSub

  @doc """
  Start a `Registry` for local pub/sub.
  """
  @spec child_spec() :: [:supervisor.child_spec()]
  @impl Commanded.PubSub
  def child_spec do
    [
      {Registry, keys: :duplicate, name: __MODULE__, partitions: System.schedulers_online()}
    ]
  end

  @doc """
  Subscribes the caller to the topic.
  """
  @spec subscribe(atom) :: :ok | {:error, term}
  @impl Commanded.PubSub
  def subscribe(topic) do
    {:ok, _} = Registry.register(__MODULE__, topic, [])
    :ok
  end

  @doc """
  Broadcasts message on given topic.
  """
  @spec broadcast(String.t(), term) :: :ok | {:error, term}
  @impl Commanded.PubSub
  def broadcast(topic, message) do
    Registry.dispatch(__MODULE__, topic, fn entries ->
      for {pid, _} <- entries, do: send(pid, message)
    end)
  end

  @doc """
  Track the current process under the given `topic`, uniquely identified by
  `key`.
  """
  @spec track(String.t(), term) :: :ok
  @impl Commanded.PubSub
  def track(topic, key) do
    {:ok, _} = Registry.register(__MODULE__, topic, key)

    :ok
  end

  @doc """
  List tracked terms and associated PIDs for a given topic.
  """
  @spec list(String.t()) :: [{term, pid}]
  @impl Commanded.PubSub
  def list(topic) do
    Registry.match(__MODULE__, topic, :_) |> Enum.map(fn {pid, key} -> {key, pid} end)
  end
end
