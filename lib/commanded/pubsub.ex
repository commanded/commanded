defmodule Commanded.PubSub do
  @moduledoc """
  Use the pubsub configured for a Commanded application.
  """

  alias Commanded.Application

  @type application :: Commanded.Application.t()
  @type config :: Keyword.t() | atom

  @doc """
  Subscribes the caller to the PubSub adapter's topic.
  """
  def subscribe(application, topic) do
    {adapter, adapter_meta} = Application.pubsub_adapter(application)

    adapter.subscribe(adapter_meta, topic)
  end

  @doc """
  Broadcasts message on given topic.

    * `topic` - The topic to broadcast to, ie: `"users:123"`
    * `message` - The payload of the broadcast

  """
  def broadcast(application, topic, message) do
    {adapter, adapter_meta} = Application.pubsub_adapter(application)

    adapter.broadcast(adapter_meta, topic, message)
  end

  @doc """
  Get the configured pub/sub adapter.

  Defaults to a local pub/sub, restricted to running on a single node.
  """
  @spec adapter(application, config) :: {module, config}
  def adapter(application, config) do
    case config do
      :local ->
        {Commanded.PubSub.LocalPubSub, []}

      adapter when is_atom(adapter) ->
        {adapter, []}

      config ->
        if Keyword.keyword?(config) do
          phoenix_pubsub_config(application, config)
        else
          raise ArgumentError,
                "invalid pubsub configured for application " <>
                  inspect(application) <> " as: " <> inspect(config)
        end
    end
  end

  defp phoenix_pubsub_config(application, config) do
    case Keyword.get(config, :phoenix_pubsub) do
      nil ->
        raise ArgumentError,
              "invalid Phoenix pubsub configuration #{inspect(config)} for application " <>
                inspect(application)

      phoenix_pubsub_config ->
        {Commanded.PubSub.PhoenixPubSub, phoenix_pubsub_config}
    end
  end
end
