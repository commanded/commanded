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

    # use mock event store adapter
    :ok = Application.put_env(:commanded, :event_store_adapter, MockEventStore)

    Application.ensure_all_started(:commanded)

    on_exit(fn ->
      Application.put_env(:commanded, :event_store_adapter, default_event_store_adapter)
      Application.stop(:commanded)
    end)

    :ok
  end
end
