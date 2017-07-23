defmodule EventStore.Subscriptions.Supervisor do
  @moduledoc """
  Supervise zero, one or more subscriptions to an event stream
  """

  use Supervisor

  def start_link do
    Supervisor.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def subscribe_to_stream(stream_uuid, subscription_name, subscriber, opts) do
    Supervisor.start_child(__MODULE__, [stream_uuid, subscription_name, subscriber, opts])
  end

  def unsubscribe_from_stream(subscription) do
    Supervisor.terminate_child(__MODULE__, subscription)
  end

  def init(_) do
    children = [
      worker(EventStore.Subscriptions.Subscription, [], restart: :temporary),
    ]

    supervise(children, strategy: :simple_one_for_one)
  end
end
