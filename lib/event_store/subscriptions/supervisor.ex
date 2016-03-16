defmodule EventStore.Subscriptions.Supervisor do
  @moduledoc """
  Supervise zero, one or more subscriptions to an event stream
  """

  use Supervisor

  def start_link do
    Supervisor.start_link(__MODULE__, nil)
  end

  def subscribe_to_stream(supervisor, stream_uuid, subscription_name, subscriber) do
    Supervisor.start_child(supervisor, [stream_uuid, subscription_name, subscriber])
  end

  def unsubscribe_from_stream(supervisor, subscription) do
    Supervisor.terminate_child(supervisor, subscription)
  end

  def init(_) do
    children = [
      worker(EventStore.Subscriptions.Subscription, [], restart: :temporary),
    ]

    supervise(children, strategy: :simple_one_for_one)
  end
end
