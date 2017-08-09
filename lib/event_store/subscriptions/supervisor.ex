defmodule EventStore.Subscriptions.Supervisor do
  @moduledoc """
  Supervise zero, one or more subscriptions to an event stream
  """

  use Supervisor

  alias EventStore.Subscriptions.Subscription

  @registry EventStore.Registration.LocalRegistry

  def start_link do
    Supervisor.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def subscribe_to_stream(stream_uuid, subscription_name, subscriber, opts) do
    @registry.register_name({stream_uuid, subscription_name}, Supervisor, :start_child, [__MODULE__, [stream_uuid, subscription_name, subscriber, opts]])
  end

  def unsubscribe_from_stream(stream_uuid, subscription_name) do
    case @registry.whereis_name({stream_uuid, subscription_name}) do
      :undefined -> :ok
      subscription ->
        :ok = Subscription.unsubscribe(subscription)
        :ok = Supervisor.terminate_child(__MODULE__, subscription)
    end
  end

  def init(_) do
    children = [
      worker(EventStore.Subscriptions.Subscription, [], restart: :temporary),
    ]

    supervise(children, strategy: :simple_one_for_one)
  end
end
