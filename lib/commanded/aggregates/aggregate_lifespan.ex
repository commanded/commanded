defmodule Commanded.Aggregates.AggregateLifespan do
  @moduledoc """
  The `Commanded.Aggregates.AggregateLifespan` behaviour is used to control an
  aggregate lifespan.

  By default an aggregate instance process will run indefinitely once started.
  You can control this by implementing the
  `Commanded.Aggregates.AggregateLifespan` behaviour in a module and configuring
  it in your router.

  After a command successfully executes, and creates at least one domain event,
  the `c:after_event/1` function is called passing the last created event. The
  returned inactivity timeout value is used to shutdown the aggregate process if
  no other messages are received.

  ## Supported return values

    - Non-negative integer - specify an inactivity timeout, in millisconds.
    - `:infinity` - prevent the aggregate instance from shutting down.
    - `:hibernate` - send the process into hibernation.
    - `:stop` - immediately shutdown the aggregate process.

  ### Hibernation

  A hibernated process will continue its loop once a message is in its message
  queue. Hibernating an aggregate causes garbage collection and minimises the
  memory used by the process. Hibernating should not be used aggressively as too
  much time could be spent garbage collecting.

  ## Example

  Define a module that implements the `Commanded.Aggregates.AggregateLifespan`
  behaviour:

      defmodule BankAccountLifespan do
        @behaviour Commanded.Aggregates.AggregateLifespan

        def after_event(%BankAccountOpened{}), do: :infinity
        def after_event(%MoneyDeposited{}), do: 60_000
        def after_event(%BankAccountClosed{}), do: :stop
      end

  Then specify the module as the `lifespan` option when registering
  the applicable commands in your router:

      defmodule BankRouter do
        use Commanded.Commands.Router

        dispatch [OpenAccount, CloseAccount],
          to: BankAccount,
          lifespan: BankAccountLifespan,
          identity: :account_number
      end

  """

  @doc """
  Aggregate process will be stopped after specified inactivity timeout unless
  `:infinity`, `:hibernate`, or `:stop` are returned.
  """
  @callback after_event(event :: struct()) :: timeout() | :hibernate | :stop
end
