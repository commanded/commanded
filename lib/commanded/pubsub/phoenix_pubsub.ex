if Code.ensure_loaded?(Phoenix.PubSub) do
  defmodule Commanded.PubSub.PhoenixPubSub do
    @moduledoc """
    Pub/sub adapter using Phoenix's distributed pub/sub and presence platform.

    To use Phoenix pub/sub you must add it as a dependency in your project's
    `mix.exs` file:

        defp deps do
          [
            {:phoenix_pubsub, "~> 1.0"}
          ]
        end

    Fetch mix deps and configure the pubsub settings in your environment config
    file:

        # `config/config.exs`
        config :my_app, MyApp.Application,
          pubsub: [
            phoenix_pubsub: [
              adapter: Phoenix.PubSub.PG2,
              pool_size: 1
            ]
          ]

    Specify the Phoenix pub/sub adapter you wish to use from:

      * `Phoenix.PubSub.PG2` - uses Distributed Elixir, directly exchanging
        notifications between servers

      * `Phoenix.PubSub.Redis` - uses Redis to exchange data between servers

    """

    @behaviour Commanded.PubSub.Adapter

    defmodule Tracker do
      @moduledoc false

      @behaviour Phoenix.Tracker

      def start_link(opts) do
        Phoenix.Tracker.start_link(__MODULE__, opts, opts)
      end

      def init(opts) do
        server = Keyword.fetch!(opts, :pubsub_server)
        state = %{pubsub_server: server, node_name: Phoenix.PubSub.node_name(server)}

        {:ok, state}
      end

      def handle_diff(_diff, state) do
        {:ok, state}
      end
    end

    @doc """
    Start the configured Phoenix pub/sub adapter and a presence tracker.
    """
    @impl Commanded.PubSub.Adapter
    def child_spec(application, config) do
      pubsub_name = Module.concat([application, PhoenixPubSub])
      tracker_name = Module.concat([application, PhoenixPubSub.Tracker])

      phoenix_pubsub_config =
        config
        |> Keyword.put(:name, pubsub_name)
        |> parse_config()

      child_spec = [
        Phoenix.PubSub.child_spec(phoenix_pubsub_config),
        %{
          id: Tracker,
          start: {Tracker, :start_link, [[name: tracker_name, pubsub_server: pubsub_name]]},
          type: :supervisor
        }
      ]

      {:ok, child_spec, %{pubsub_name: pubsub_name, tracker_name: tracker_name}}
    end

    @doc """
    Subscribes the caller to the topic.
    """
    @impl Commanded.PubSub.Adapter
    def subscribe(adapter_meta, topic) when is_binary(topic) do
      name = pubsub_name(adapter_meta)

      Phoenix.PubSub.subscribe(name, topic)
    end

    @doc """
    Broadcasts message on given topic.
    """
    @impl Commanded.PubSub.Adapter
    def broadcast(adapter_meta, topic, message) when is_binary(topic) do
      name = pubsub_name(adapter_meta)

      Phoenix.PubSub.broadcast(name, topic, message)
    end

    @doc """
    Track the current process under the given `topic`, uniquely identified by
    `key`.
    """
    @impl Commanded.PubSub.Adapter
    def track(adapter_meta, topic, key) when is_binary(topic) do
      name = tracker_name(adapter_meta)

      case Phoenix.Tracker.track(name, self(), topic, key, %{pid: self()}) do
        {:ok, _ref} -> :ok
        {:error, {:already_tracked, _pid, _topic, _key}} -> :ok
        reply -> reply
      end
    end

    @doc """
    List tracked terms and associated PIDs for a given topic.
    """
    @impl Commanded.PubSub.Adapter
    def list(adapter_meta, topic) when is_binary(topic) do
      name = tracker_name(adapter_meta)

      Phoenix.Tracker.list(name, topic) |> Enum.map(fn {key, %{pid: pid}} -> {key, pid} end)
    end

    defp parse_config(config) do
      Enum.map(config, fn
        {key, {:system, env}} when key in [:port, :pool_size] ->
          {key, env |> System.get_env() |> String.to_integer()}

        {key, {:system, env}} ->
          {key, System.get_env(env)}

        pair ->
          pair
      end)
    end

    defp pubsub_name(adapter_meta), do: Map.get(adapter_meta, :pubsub_name)
    defp tracker_name(adapter_meta), do: Map.get(adapter_meta, :tracker_name)
  end
end
