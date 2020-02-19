defmodule Commanded.Aggregates.Supervisor do
  @moduledoc """
  Supervises `Commanded.Aggregates.Aggregate` instance processes.
  """

  use DynamicSupervisor

  require Logger

  alias Commanded.Aggregates.Aggregate
  alias Commanded.Registration

  def child_spec(arg) do
    application = Keyword.fetch!(arg, :application)
    Registration.supervisor_child_spec(application, __MODULE__, arg)
  end

  def start_link(args) do
    application = Keyword.fetch!(args, :application)
    name = Module.concat([application, __MODULE__])

    DynamicSupervisor.start_link(__MODULE__, args, name: name)
  end

  @doc """
  Open an aggregate instance process for the given aggregate module and unique
  identity.

  Returns `{:ok, aggregate_uuid}` when a process is sucessfully started, or is
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
