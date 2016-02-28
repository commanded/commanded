defmodule EventStore.Subscriptions.Supervisor do
  use Supervisor

  def start_link(storage) do
    Supervisor.start_link(__MODULE__, storage)
  end

  def subscribe_to_stream(supervisor, stream_uuid, subscription_name, subscriber) do
    Supervisor.start_child(supervisor, [stream_uuid, subscription_name, subscriber])
  end

  def init(storage) do
    children = [
      worker(EventStore.Subscriptions.Subscription, [storage], restart: :temporary),
    ]
    supervise(children, strategy: :simple_one_for_one)
  end
end
