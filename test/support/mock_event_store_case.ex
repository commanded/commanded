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

  setup [:set_mox_global, :stub_event_store]

  setup do
    start_supervised!(MockedApp)

    :ok
  end

  def stub_event_store(_context) do
    stub(MockEventStore, :ack_event, fn _event_store_meta, _subscription, _ack ->
      :ok
    end)

    stub(MockEventStore, :child_spec, fn _application, _config ->
      {:ok, [], %{}}
    end)

    stub(MockEventStore, :subscribe_to, fn
      _event_store_meta, _stream, _handler_name, subscriber, _subscribe_from, _opts ->
        send(subscriber, {:subscribed, self()})

        {:ok, self()}
    end)

    :ok
  end
end
