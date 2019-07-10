defmodule Commanded.ConfigureSnapshotting do
  def configure_snapshotting(application, aggregate_module, opts) do
    config = Application.get_env(:commanded, application)

    snapshotting =
      config
      |> Keyword.get(:snapshotting, %{})
      |> Map.put(aggregate_module, opts)

    config = Keyword.put(config, :snapshotting, snapshotting)

    Application.put_env(:commanded, application, config)
  end

  def unconfigure_snapshotting(application, aggregate_module) do
    configure_snapshotting(application, aggregate_module, [])
  end
end
