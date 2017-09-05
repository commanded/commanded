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
    :ok = Application.stop(:swarm)
    :ok = Application.stop(:eventstore)

    Enum.each(nodes(), fn node ->
      :ok = EventStore.Cluster.rpc(node, Application, :stop, [:eventstore])
    end)
  end

  defp before_reset(_registry) do
    Application.stop(:eventstore)
  end

  defp after_reset(EventStore.Registration.Distributed) do
    {:ok, _} = Application.ensure_all_started(:eventstore)

    Enum.each(nodes(), fn node ->
      EventStore.Cluster.rpc(node, Application, :ensure_all_started, [:eventstore])
    end)
  end

  defp after_reset(_registry) do
    {:ok, _} = Application.ensure_all_started(:eventstore)
  end

  defp nodes, do: Node.list(:connected)
end
