defmodule Commanded.Commands.Handler do
  @moduledoc """
  Defines the behaviour a command handler module must implement to support command dispatch.

  ## Example

  An open account handler that delegates to a bank account aggregate:

      defmodule OpenAccountHandler do
        @behaviour Commanded.Commands.Handler

        def handle(%BankAccount{} = aggregate, %OpenAccount{} = command) do
          %OpenAccount{account_number: account_number, initial_balance: initial_balance} = command

          BankAccount.open_account(aggregate, account_number, initial_balance)
        end
      end
  """

  @type aggregate :: struct()
  @type command :: struct()
  @type domain_event :: struct
  @type reason :: any()

  @doc """
  Apply the given command to the event sourced aggregate.

  You must return a single domain event, a list containing the pending events,
  or `nil`, `[]`, or `:ok` when no events are produced.

  You should return `{:error, reason}` on failure.
  """
  @callback handle(aggregate, command) ::
              domain_event
              | list(domain_event)
              | {:ok, domain_event}
              | {:ok, list(domain_event)}
              | :ok
              | nil
              | {:error, reason}
end
