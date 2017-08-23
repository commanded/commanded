defmodule EventStore.StorageCase do
  use ExUnit.CaseTemplate
  use EventStore.Registration

  import ExUnit.Assertions

  alias EventStore.Wait

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

    expected_node_count = Application.get_env(:swarm, :nodes, []) |> length()

    Wait.until(5_000, fn ->
      assert length(@registry.members(EventStore.Publisher)) >= expected_node_count
    end)
  end

  defp after_reset(_registry) do
    {:ok, _} = Application.ensure_all_started(:eventstore)
  end
end
