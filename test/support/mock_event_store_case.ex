defmodule Commanded.MockEventStoreCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  import Mox

  alias Commanded.EventStore.Adapters.Mock, as: MockEventStore

  using do
    quote do
      import Mox

      alias Commanded.EventStore.Adapters.Mock, as: MockEventStore
    end
  end

  setup do
    set_mox_global()

    default_event_store_adapter = Application.get_env(:commanded, :event_store_adapter)

    # Use mock event store adapter
    use_event_store_adapter(MockEventStore)

    on_exit(fn ->
      use_event_store_adapter(default_event_store_adapter)
    end)
  end

  defp use_event_store_adapter(adapter) do
    expect(MockEventStore, :child_spec, fn -> [] end)

    :ok = Application.stop(:commanded)

    Application.put_env(:commanded, :event_store_adapter, adapter)

    {:ok, _apps} = Application.ensure_all_started(:commanded)
  end
end
