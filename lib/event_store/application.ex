defmodule EventStore.Application do
  use Application

  def start(_, _) do
    config = EventStore.configuration() |> EventStore.Config.parse()
    
    EventStore.Supervisor.start_link(config)
  end
end
