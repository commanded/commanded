defmodule Commanded.Application.ConfigBench do
  use Benchfella

  alias Commanded.Application.Config
  alias Commanded.ExampleApplication

  setup_all do
    {:ok, _apps} = Application.ensure_all_started(:commanded)
    {:ok, pid} = ExampleApplication.start_link()

    {:ok, pid}
  end

  bench "lookup config" do
    {_adapter, _config} = Config.get(ExampleApplication, :event_store)
  end
end
