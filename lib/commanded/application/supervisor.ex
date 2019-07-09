defmodule Commanded.Application.Supervisor do
  @moduledoc false

  use Supervisor

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
  def runtime_config(application, otp_app, opts) do
    config =
      Application.get_env(otp_app, application, [])
      |> Keyword.merge(opts)
      |> Keyword.merge(otp_app: otp_app)

    case application_init(application, config) do
      {:ok, config} -> {:ok, config}
      :ignore -> :ignore
    end
  end

  @doc """
  Starts the application supervisor.
  """
  def start_link(application, otp_app, event_store, pubsub, registry, opts) do
    sup_opts = if name = Keyword.get(opts, :name, application), do: [name: name], else: []

    Supervisor.start_link(
      __MODULE__,
      {application, otp_app, event_store, registry, pubsub, opts},
      sup_opts
    )
  end

  def init({application, otp_app, event_store, pubsub, registry, opts}) do
    case runtime_config(application, otp_app, opts) do
      {:ok, _config} ->
        task_dispatcher_name = Module.concat([application, Commanded.Commands.TaskDispatcher])
        subscriptions_name = Module.concat([application, Commanded.Subscriptions])

        children =
          event_store.child_spec() ++
            pubsub.child_spec() ++
            registry.child_spec() ++
            [
              {Task.Supervisor, name: task_dispatcher_name},
              {Commanded.Aggregates.Supervisor, application: application},
              Commanded.Subscriptions.Registry,
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
