defmodule Commanded.PubSub.Adapter do
  @moduledoc false

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @adapter Keyword.fetch!(opts, :adapter)
      @config Keyword.fetch!(opts, :config)

      @behaviour Commanded.PubSub.Adapter

      def child_spec, do: @adapter.child_spec(__MODULE__, @config)

      def subscribe(topic), do: @adapter.subscribe(__MODULE__, topic)

      def broadcast(topic, message), do: @adapter.broadcast(__MODULE__, topic, message)

      def track(topic, key), do: @adapter.broadcast(__MODULE__, topic, key)

      def list(topic), do: @adapter.list(__MODULE__, topic)
    end
  end

  @doc """
  Return an optional supervisor spec for pub/sub.
  """
  @callback child_spec() :: [:supervisor.child_spec()]

  @doc """
  Subscribes the caller to the PubSub topic.
  """
  @callback subscribe(topic :: String.t()) :: :ok | {:error, term}

  @doc """
  Broadcasts message on given topic.

    * `topic` - The topic to broadcast to, ie: `"users:123"`
    * `message` - The payload of the broadcast

  """
  @callback broadcast(topic :: String.t(), message :: term) :: :ok | {:error, term}

  @doc """
  Track the current process under the given `topic`, uniquely identified by
  `key`.
  """
  @callback track(String.t(), key :: term) :: :ok | {:error, term}

  @doc """
  List tracked PIDs for a given topic.
  """
  @callback list(String.t()) :: [{term, pid}]
end
