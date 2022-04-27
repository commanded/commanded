defmodule Commanded.Aggregates.Supervisor do
  @moduledoc """
  Supervises `Commanded.Aggregates.Aggregate` instance processes.
  """

  use DynamicSupervisor

  require Logger

  alias Commanded.Aggregates.Aggregate
  alias Commanded.Registration

  def start_link(opts) do
    {start_opts, supervisor_opts} =
      Keyword.split(opts, [:debug, :name, :timeout, :spawn_opt, :hibernate_after])

    DynamicSupervisor.start_link(__MODULE__, supervisor_opts, start_opts)
  end

  @doc """
  Open an aggregate instance process for the given aggregate module and unique
  identity.

  Returns `{:ok, aggregate_uuid}` when a process is successfully started, or is
  already running.
  """
  def open_aggregate(application, aggregate_module, aggregate_uuid)
      when is_atom(application) and is_atom(aggregate_module) and is_binary(aggregate_uuid) do
    Logger.debug(fn ->
      "Locating aggregate process for `#{inspect(aggregate_module)}` with UUID " <>
        inspect(aggregate_uuid)
    end)

    supervisor_name = Module.concat([application, __MODULE__])
    aggregate_name = Aggregate.name(application, aggregate_module, aggregate_uuid)

    args = [
      application: application,
      aggregate_module: aggregate_module,
      aggregate_uuid: aggregate_uuid
    ]

    case Registration.start_child(application, aggregate_name, supervisor_name, {Aggregate, args}) do
      {:ok, _pid} ->
        {:ok, aggregate_uuid}

      {:ok, _pid, _info} ->
        {:ok, aggregate_uuid}

      {:error, {:already_started, _pid}} ->
        {:ok, aggregate_uuid}

      reply ->
        reply
    end
  end

  def open_aggregate(_application, _aggregate_module, aggregate_uuid),
    do: {:error, {:unsupported_aggregate_identity_type, aggregate_uuid}}

  def init(args) do
    DynamicSupervisor.init(strategy: :one_for_one, extra_arguments: [args])
  end
end
