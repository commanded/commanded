defmodule Commanded.Event.AppendingEventHandler do
  @moduledoc false

  use Commanded.Event.Handler,
    application: Commanded.DefaultApp,
    name: __MODULE__

  def after_start(_state) do
    with {:ok, _pid} <- Agent.start_link(fn -> %{events: [], metadata: []} end, name: __MODULE__) do
      :ok
    end
  end

  def handle(event, event_metadata) do
    Agent.update(__MODULE__, fn %{events: events, metadata: metadata} ->
      %{events: events ++ [event], metadata: metadata ++ [event_metadata]}
    end)
  end

  def subscribed? do
    try do
      Agent.get(__MODULE__, fn _ -> true end)
    catch
      :exit, _reason -> false
    end
  end

  def received_events do
    try do
      Agent.get(__MODULE__, fn %{events: events} -> events end)
    catch
      :exit, _reason -> []
    end
  end

  def received_metadata do
    try do
      Agent.get(__MODULE__, fn %{metadata: metadata} -> metadata end)
    catch
      :exit, _reason -> []
    end
  end
end
