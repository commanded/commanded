defmodule Commanded.Commands.Handler do
  @moduledoc """
  Defines the behaviour a command handler module must implement to support command dispatch.

  ## Example

  An open account handler that delegates to a bank account aggregate root:
  
      defmodule OpenAccountHandler do
        @behaviour Commanded.Commands.Handler

        def handle(%BankAccount{} = aggregate, %OpenAccount{account_number: account_number, initial_balance: initial_balance}) do
          BankAccount.open_account(aggregate, account_number, initial_balance)
        end
      end
  """

  @type aggregate :: struct()
  @type command :: struct()
  @type domain_event :: struct
  @type domain_events :: list(struct())
  @type reason :: term()

  @doc """
  Apply the given command to the event sourced aggregate root.

  You must return a list containing the pending events, or `nil` / `[]` when no events produced.

  You should return `{:error, reason}` on failure.
  """
  @callback handle(aggregate, command) :: domain_event | domain_events | nil | {:error, reason}
end
