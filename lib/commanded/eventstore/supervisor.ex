defmodule Commanded.EventStore.Supervisor do
  use Supervisor

  use Commanded.EventStore

  def start_link do
    Supervisor.start_link(__MODULE__, nil)
  end

  def init(_) do
    extreme_settings = Commanded.Config.get :commanded, :extreme

    children = [worker(Commanded.Aggregates.Registry, [])] ++
      case @event_store do
	Commanded.EventStore.Adapters.EventStoreEventStore -> [
	  worker(Commanded.EventStore.Adapters.EventStoreEventStore, [])
	]
	Commanded.EventStore.Adapters.ExtremeEventStore -> [
	  worker(Extreme, [extreme_settings, [name: Commanded.ExtremeEventStore]]),
	  worker(Commanded.EventStore.Adapters.ExtremeEventStore, [])
	]
      end

    supervise(children, strategy: :one_for_all)
  end
end
