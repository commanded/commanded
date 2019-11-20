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

    case application_init(application, config) do
      {:ok, config} -> {:ok, config}
      :ignore -> :ignore
    end
  end

  @doc """
  Starts the application supervisor.
  """
  def start_link(application, otp_app, config, opts) do
    sup_opts = if name = Keyword.get(opts, :name, application), do: [name: name], else: []

    Supervisor.start_link(
      __MODULE__,
      {application, otp_app, config, opts},
      sup_opts
    )
  end

  def init({application, otp_app, config, opts}) do
    case runtime_config(application, otp_app, config, opts) do
      {:ok, config} ->
        {event_store_child_spec, config} = event_store_child_spec(application, config)
        {pubsub_child_spec, config} = pubsub_child_spec(application, config)
        {registry_child_spec, config} = registry_child_spec(application, config)

        :ok = Config.associate(self(), application, config)

        children =
          event_store_child_spec ++
            pubsub_child_spec ++
            registry_child_spec ++
            commanded_child_spec(application, config)

        Supervisor.init(children, strategy: :one_for_one)

      :ignore ->
        :ignore
    end
  end

  defp commanded_child_spec(application, config) do
    task_dispatcher_name = Module.concat([application, Commanded.Commands.TaskDispatcher])
    subscriptions_name = Module.concat([application, Commanded.Subscriptions])
    registry_name = Module.concat([application, Commanded.Subscriptions.Registry])
    snapshotting = Keyword.get(config, :snapshotting, %{})

    [
      {Task.Supervisor, name: task_dispatcher_name},
      {Commanded.Aggregates.Supervisor, application: application, snapshotting: snapshotting},
      {Commanded.Subscriptions.Registry, application: application, name: registry_name},
      {Commanded.Subscriptions, application: application, name: subscriptions_name}
    ]
  end

  defp event_store_child_spec(application, config) do
    {adapter, adapter_config} =
      Commanded.EventStore.adapter(application, Keyword.get(config, :event_store))

    {:ok, child_spec, adapter_meta} = adapter.child_spec(application, adapter_config)

    config = Keyword.put(config, :event_store, {adapter, adapter_meta})

    {child_spec, config}
  end

  defp pubsub_child_spec(application, config) do
    {adapter, adapter_config} =
      Commanded.PubSub.adapter(application, Keyword.get(config, :pubsub, :local))

    {:ok, child_spec, adapter_meta} = adapter.child_spec(application, adapter_config)

    config = Keyword.put(config, :pubsub, {adapter, adapter_meta})

    {child_spec, config}
  end

  defp registry_child_spec(application, config) do
    {adapter, adapter_config} =
      Commanded.Registration.adapter(application, Keyword.get(config, :registry, :local))

    {:ok, child_spec, adapter_meta} = adapter.child_spec(application, adapter_config)

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
