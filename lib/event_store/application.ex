defmodule EventStore.Application do
  use Application

  alias EventStore.Config

  def start(_, _) do
    config = EventStore.configuration() |> Config.parse()

    EventStore.Supervisor.start_link(config)
  end
end
