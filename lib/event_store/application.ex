defmodule EventStore.Application do
  use Application

  def start(_, _) do
    EventStore.Supervisor.start_link
  end
end
