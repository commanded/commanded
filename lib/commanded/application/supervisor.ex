defmodule Commanded.Application.Supervisor do
  @moduledoc false

  use Supervisor

  alias Commanded.Application.Config

  @doc """
  Retrieves the compile time configuration.
  """
  def compile_config(application, opts) do
    otp_app = Keyword.fetch!(opts, :otp_app)
    env_opts = Application.get_env(otp_app, application, [])

    config = Keyword.merge(opts, env_opts)

    {otp_app, config}
  end

  @doc """
  Retrieves the runtime configuration.
  """
  def runtime_config(application, otp_app, config, opts) do
    config =
      config
      |> Keyword.merge(opts)
      |> Keyword.put(:otp_app, otp_app)
      |> Keyword.put(:application, application)

    case application_init(application, config) do
      {:ok, config} -> {:ok, config}
      :ignore -> :ignore
    end
  end

  @doc """
  Starts the application supervisor.
  """
  def start_link(application, otp_app, config, name, opts) do
    Supervisor.start_link(
      __MODULE__,
      {application, otp_app, config, name, opts},
      name: name
    )
  end

  def init({application, otp_app, config, name, opts}) do
    case runtime_config(application, otp_app, config, opts) do
      {:ok, config} ->
        {event_store_child_spec, config} = event_store_child_spec(name, config)
        {pubsub_child_spec, config} = pubsub_child_spec(name, config)
        {registry_child_spec, config} = registry_child_spec(name, config)

        :ok = Config.associate(self(), name, config)

        children =
          event_store_child_spec ++
            pubsub_child_spec ++
            registry_child_spec ++
            app_child_spec(name, config)

        Supervisor.init(children, strategy: :one_for_one)

      :ignore ->
        :ignore
    end
  end

  defp app_child_spec(name, config) do
    task_dispatcher_name = Module.concat([name, Commanded.Commands.TaskDispatcher])
    aggregates_supervisor_name = Module.concat([name, Commanded.Aggregates.Supervisor])
    subscriptions_name = Module.concat([name, Commanded.Subscriptions])
    registry_name = Module.concat([name, Commanded.Subscriptions.Registry])
    snapshotting = Keyword.get(config, :snapshotting, %{})
    hibernate_after = Keyword.get(config, :hibernate_after, :infinity)

    [
      {Task.Supervisor, name: task_dispatcher_name, hibernate_after: hibernate_after},
      {Commanded.Aggregates.Supervisor,
       name: aggregates_supervisor_name,
       application: name,
       snapshotting: snapshotting,
       hibernate_after: hibernate_after},
      {Commanded.Subscriptions.Registry,
       application: name, name: registry_name, hibernate_after: hibernate_after},
      {Commanded.Subscriptions,
       application: name, name: subscriptions_name, hibernate_after: hibernate_after}
    ]
  end

  defp event_store_child_spec(name, config) do
    {adapter, adapter_config} =
      Commanded.EventStore.adapter(name, Keyword.get(config, :event_store))

    {:ok, child_spec, adapter_meta} = adapter.child_spec(name, adapter_config)

    config = Keyword.put(config, :event_store, {adapter, adapter_meta})

    {child_spec, config}
  end

  defp pubsub_child_spec(name, config) do
    {adapter, adapter_config} =
      Commanded.PubSub.adapter(name, Keyword.get(config, :pubsub, :local))

    {:ok, child_spec, adapter_meta} = adapter.child_spec(name, adapter_config)

    config = Keyword.put(config, :pubsub, {adapter, adapter_meta})

    {child_spec, config}
  end

  defp registry_child_spec(name, config) do
    {adapter, adapter_config} =
      Commanded.Registration.adapter(name, Keyword.get(config, :registry, :local))

    {:ok, child_spec, adapter_meta} = adapter.child_spec(name, adapter_config)

    config = Keyword.put(config, :registry, {adapter, adapter_meta})

    {child_spec, config}
  end

  defp application_init(application, config) do
    if Code.ensure_loaded?(application) and function_exported?(application, :init, 1) do
      application.init(config)
    else
      {:ok, config}
    end
  end
end
