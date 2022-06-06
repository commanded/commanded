defmodule Commanded.Event.ConcurrentEventHandler do
  @moduledoc false
  alias Commanded.Event.ConcurrencyEvent

  use Commanded.Event.Handler,
    application: Commanded.DefaultApp,
    name: __MODULE__,
    concurrency: 5

  @impl Commanded.Event.Handler
  def init do
    Process.send(:test, {:init, self()}, [])
  end

  @impl Commanded.Event.Handler
  def init(config) do
    Process.send(:test, {:init, config, self()}, [])

    {:ok, config}
  end

  @impl Commanded.Event.Handler
  def handle(%ConcurrencyEvent{} = event, _metadata) do
    %ConcurrencyEvent{stream_uuid: stream_uuid} = event

    Process.send(:test, {:event, stream_uuid, self()}, [])
  end
end
