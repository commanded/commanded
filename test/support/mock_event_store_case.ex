defmodule Commanded.MockEventStoreCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  import Mox

  alias Commanded.EventStore.Adapters.Mock, as: MockEventStore
  alias Commanded.MockedApp

  using do
    quote do
      import Mox

      alias Commanded.EventStore.Adapters.Mock, as: MockEventStore
    end
  end

  setup do
    set_mox_global()

    expect(MockEventStore, :child_spec, fn _application, _config -> [] end)

    start_supervised!(MockedApp)

    :ok
  end
end
