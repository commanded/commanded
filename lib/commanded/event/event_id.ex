defprotocol Commanded.Event.EventId do
  @moduledoc """
  Protocol to define a unique event identifier for domain events.

  By default, a random UUID is generated for each event at the event store
  level, but you can implement this protocol for your events to provide a unique
  ID.

  > #### Adapter Implementation {: .warning}
  >
  > Make sure to implement the `Commanded.Event.EventId` protocol support for
  > your adapter implementation.

  > #### Uniqueness and Format {: .warning}
  >
  > The event ID must be a valid UUID and unique across the entire event store.

  ## When to leverage the event ID

  The event ID is included in the persisted event data and provides a reliable
  way to ensure idempotency - guaranteeing that each event is only processed
  once, even in failure scenarios.

  This is particularly useful when dealing with dual-write problems, where a
  command may need to be retried due to failures in acknowledgement or
  processing. Rather than storing idempotency keys in aggregate state
  (which introduces complexity around state management), the event ID can be
  used as a natural idempotency key at the event store level.

  Using event IDs for idempotency avoids several challenging questions that
  arise when storing idempotency keys in aggregate state:

  - Managing the number of stored IDs to prevent unbounded growth
  - Determining appropriate retention periods for stored IDs
  - Implementing ID expiration logic
  - Handling the memory overhead of stored IDs

  The event store's built-in duplicate detection using event IDs provides a
  simpler and more robust solution to these challenges.

  We can use the `event_id` as a unique identifier to guarantee idempotency at
  the event store level, where duplicate event IDs will be rejected. You detect
  the duplicate and could be treated as a success.

  > #### `EventStore` Error Handling {: .info}
  >
  > The `EventStore` will return `{:error, :duplicate_event}` if the event ID
  > is already in the event store. You can handle this error and treat it as a
  > success.

  Example:

  > The following example is a simplified example, and it would apply to any
  > dual-write problems, not just `Commanded.Event.Handler`s.

  Imagine you have a `Transfer` workflow that needs to communicate with the
  `BankAccount` aggregate. The `Transfer` will debit the sender's account and
  credit the recipient's account after `TransferDebitRequested` or
  `TransferCreditRequested` event is received.

  ```elixir
  defmodule Transferer do
    use Commanded.Event.Handler,
      application: BankApp,
      name: __MODULE__

    @impl Commanded.Event.Handler
    def handle(%TransferDebitRequested{transfer_id: transfer_id, account_id: account_id}, _metadata) do
      :ok = BankApp.dispatch(%DebitAccount{account_id: account_id, amount: amount})
    end

    @impl Commanded.Event.Handler
    def handle(%TransferCreditRequested{transfer_id: transfer_id, account_id: account_id}, _metadata) do
      :ok = BankApp.dispatch(%CreditAccount{account_id: account_id, amount: amount})
    end
  end
  ```

  The dispatching of the commands may succeed, but acknowledgement of the event
  may fail, resulting in a retrying of the event. You could combine the
  `Transfer` and `Event ID` to create a deterministic idempotency key.

  ```elixir
  defmodule Transferer do
    use Commanded.Event.Handler,
      application: BankApp,
      name: __MODULE__

    @impl Commanded.Event.Handler
    def handle(%TransferDebitRequested{transfer_id: transfer_id, account_id: account_id}, %{event_id: event_id}) do
      cmd = %DebitAccount{
        account_id: account_id,
        amount: amount,
        idempotency_key: Uniq.UUID.uuid5(transfer_id, event_id)
      }

      with {:error, :duplicate_event} <- BankApp.dispatch(cmd) do
        # treat the duplicate event as a success, it means the command was already processed
        :ok
      end
    end

    @impl Commanded.Event.Handler
    def handle(%TransferCreditRequested{transfer_id: transfer_id, account_id: account_id}, %{event_id: event_id}) do
      cmd = %CreditAccount{
        account_id: account_id,
        amount: amount,
        idempotency_key: Uniq.UUID.uuid5(transfer_id, event_id)
      }

      with {:error, :duplicate_event} <- BankApp.dispatch(cmd) do
        # treat the duplicate event as a success, it means the command was already processed
        :ok
      end
    end
  end
  ```

  The `BankAccount` will emit a `AccountDebited` and `AccountCredited` event.

  ```elixir
  defmodule BankAccountCredited do
    defstruct [:account_id, :amount, :idempotency_key]

    defimpl Commanded.Event.EventId do
      def event_id(%BankAccountCredited{idempotency_key: idempotency_key}) do
        idempotency_key
      end
    end
  end

  defmodule BankAccountDebited do
    defstruct [:account_id, :amount, :idempotency_key]

    defimpl Commanded.Event.EventId do
      def event_id(%BankAccountDebited{idempotency_key: idempotency_key}) do
        idempotency_key
      end
    end
  end
  ```
  """

  @doc """
  Get the event ID for the given event. If the return value is `nil`, a UUID
  will be generated by the Event Store.
  """
  @fallback_to_any true
  @spec event_id(event :: struct()) :: Commanded.EventStore.EventData.uuid() | nil
  def event_id(event)
end

defimpl Commanded.Event.EventId, for: Any do
  def event_id(_event), do: nil
end
