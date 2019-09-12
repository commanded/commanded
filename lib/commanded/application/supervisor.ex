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
  def start_link(application, otp_app, event_store, pubsub, registry, config, opts) do
    sup_opts = if name = Keyword.get(opts, :name, application), do: [name: name], else: []

    Supervisor.start_link(
      __MODULE__,
      {application, otp_app, event_store, registry, pubsub, config, opts},
      sup_opts
    )
  end

  def init({application, otp_app, event_store, pubsub, registry, config, opts}) do
    case runtime_config(application, otp_app, config, opts) do
      {:ok, config} ->
        :ok = Config.associate(self(), config)

        task_dispatcher_name = Module.concat([application, Commanded.Commands.TaskDispatcher])
        subscriptions_name = Module.concat([application, Commanded.Subscriptions])
        registry_name = Module.concat([application, Commanded.Subscriptions.Registry])
        snapshotting = Keyword.get(config, :snapshotting, %{})

        children =
          event_store.child_spec(Keyword.get(config, :event_store, [])) ++
            pubsub.child_spec(Keyword.get(config, :pubsub, [])) ++
            registry.child_spec(Keyword.get(config, :registry, [])) ++
            [
              {Task.Supervisor, name: task_dispatcher_name},
              {Commanded.Aggregates.Supervisor,
               application: application, snapshotting: snapshotting},
              {Commanded.Subscriptions.Registry, application: application, name: registry_name},
              {Commanded.Subscriptions, application: application, name: subscriptions_name}
            ]

        Supervisor.init(children, strategy: :one_for_one)

      :ignore ->
        :ignore
    end
  end

  defp application_init(application, config) do
    if Code.ensure_loaded?(application) and function_exported?(application, :init, 1) do
      application.init(config)
    else
      {:ok, config}
    end
  end
end
