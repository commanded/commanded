defmodule EventStore.StorageInitializer do
  use EventStore.Registration
  import ExUnit.Assertions

  alias EventStore.{Storage,Wait}

  def reset_storage! do
    before_reset(@registry)

    with {:ok, conn} <- EventStore.configuration() |> EventStore.Config.parse() |> Postgrex.start_link() do
      Storage.Initializer.reset!(conn)
    end

    after_reset(@registry)

    :ok
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

    Wait.until(fn ->
      assert length(@registry.members(EventStore.Publisher)) >= 2
    end)
  end

  defp after_reset(_registry) do
    {:ok, _} = Application.ensure_all_started(:eventstore)
  end
end
