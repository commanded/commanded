defmodule Commanded.Aggregates.ExecutionContext do
  @moduledoc """
  Defines the arguments used to execute a command for an aggregate.

  The available options are:

    - `command` - the command to execute, typically a struct
      (e.g. `%OpenBankAccount{...}`).

    - `retry_attempts` - the number of retries permitted if an
      `{:error, :wrong_expected_version}` is encountered when appending events.

    - `causation_id` - the UUID assigned to the dispatched command.

    - `correlation_id` - a UUID used to correlate related commands/events.

    - `metadata` - a map of key/value pairs containing the metadata to be
      associated with all events created by the command.

    - `handler` - the module that handles the command. It may be either the
      aggregate module itself or a separate command handler module.

    - `function` - the name of the function, as an atom, that handles the command.
      The default value is `:execute`, used to support command dispatch directly
      to the aggregate module. For command handlers the `:handle` function is
      used.

    - `before_execute` - the name of the function, as an atom, that prepares the
      command before execution, called just before `function`. The default value
      is `nil`, disabling it. It should return `:ok` on success or `{:error, any()}`
      to cancel the dispatch.

    - `lifespan` - a module implementing the `Commanded.Aggregates.AggregateLifespan`
      behaviour to control the aggregate instance process lifespan. The default
      value, `Commanded.Aggregates.DefaultLifespan`, keeps the process running
      indefinitely.

  """

  alias Commanded.Aggregates.Aggregate
  alias Commanded.Aggregates.DefaultLifespan
  alias Commanded.Aggregates.ExecutionContext
  alias Commanded.Commands.ExecutionResult

  defstruct [
    :command,
    :causation_id,
    :correlation_id,
    :handler,
    :function,
    before_execute: nil,
    retry_attempts: 0,
    returning: false,
    lifespan: DefaultLifespan,
    metadata: %{}
  ]

  def retry(%ExecutionContext{retry_attempts: nil}),
    do: {:error, :too_many_attempts}

  def retry(%ExecutionContext{retry_attempts: retry_attempts}) when retry_attempts <= 0,
    do: {:error, :too_many_attempts}

  def retry(%ExecutionContext{} = context) do
    %ExecutionContext{retry_attempts: retry_attempts} = context

    context = %ExecutionContext{context | retry_attempts: retry_attempts - 1}

    {:ok, context}
  end

  def format_reply({:ok, events}, %ExecutionContext{} = context, %Aggregate{} = aggregate) do
    %Aggregate{
      aggregate_uuid: aggregate_uuid,
      aggregate_state: aggregate_state,
      aggregate_version: aggregate_version
    } = aggregate

    %ExecutionContext{metadata: metadata, returning: returning} = context

    case returning do
      :aggregate_state ->
        {:ok, aggregate_version, events, aggregate_state}

      :aggregate_version ->
        {:ok, aggregate_version, events, aggregate_version}

      :events ->
        {:ok, aggregate_version, events, events}

      :execution_result ->
        result = %ExecutionResult{
          aggregate_uuid: aggregate_uuid,
          aggregate_state: aggregate_state,
          aggregate_version: aggregate_version,
          events: events,
          metadata: metadata
        }

        {:ok, aggregate_version, events, result}

      false ->
        {:ok, aggregate_version, events}
    end
  end

  def format_reply({:error, _error} = reply, _context, _aggregate) do
    reply
  end

  def format_reply({:error, error, _stacktrace}, _context, _aggregate) do
    {:error, error}
  end
end
