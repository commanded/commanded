defmodule Commanded.Event.AppendingEventHandler do
  def start_link do
    Agent.start_link(fn -> [] end, name: __MODULE__)
  end

  def handle(event) do
    Agent.update(__MODULE__, fn events -> [event|events] end)
  end

  def received_events do
    Agent.get(__MODULE__, fn events -> Enum.reverse(events) end)
  end
end
