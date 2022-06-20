defmodule Commanded.Event.PartitionEventHandler do
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

  @impl Commanded.Event.Handler
  def partition_by(%ConcurrencyEvent{} = event, metadata) do
    %ConcurrencyEvent{partition: partition} = event

    Process.send(:test, {:partition_by, event, metadata}, [])

    partition
  end
end
