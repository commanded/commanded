defmodule EventStore.StorageCase do
  use ExUnit.CaseTemplate
  use EventStore.Registration

  setup do
    before_reset(@registry)

    EventStore.StorageInitializer.reset_storage!()

    after_reset(@registry)

    {:ok, conn} = EventStore.configuration() |> EventStore.Config.parse() |> Postgrex.start_link()

    {:ok, %{conn: conn}}
  end

  defp before_reset(EventStore.Registration.Distributed) do
    Application.stop(:swarm)
    Application.stop(:eventstore)
  end

  defp before_reset(_registry) do
    Application.stop(:eventstore)
  end

  # wait until the publisher processes have registered themselves
  defp after_reset(EventStore.Registration.Distributed) do
    {:ok, _} = Application.ensure_all_started(:swarm)
    {:ok, _} = Application.ensure_all_started(:eventstore)
  end

  defp after_reset(_registry) do
    {:ok, _} = Application.ensure_all_started(:eventstore)
  end
end
