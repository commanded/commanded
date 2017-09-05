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

    nodes()
    |> Enum.map(&Task.async(fn ->
      :ok = EventStore.Cluster.rpc(&1, Application, :stop, [:eventstore])
    end))
    |> Enum.map(&Task.await(&1, 5_000))
  end

  defp before_reset(_registry) do
    Application.stop(:eventstore)
  end

  defp after_reset(EventStore.Registration.Distributed) do
    nodes()
    |> Enum.map(&Task.async(fn ->
      {:ok, _} = EventStore.Cluster.rpc(&1, Application, :ensure_all_started, [:swarm])
      {:ok, _} = EventStore.Cluster.rpc(&1, Application, :ensure_all_started, [:eventstore])
    end))
    |> Enum.map(&Task.await(&1, 5_000))
  end

  defp after_reset(_registry) do
    {:ok, _} = Application.ensure_all_started(:eventstore)
  end

  defp nodes, do: [Node.self() | Node.list(:connected)]
end
