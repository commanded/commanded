defmodule Commanded.Aggregate.Multi do
  @moduledoc """
  Use `Commanded.Aggregate.Multi` to generate multiple events from a single
  command.

  This can be useful when you want to emit multiple events that depend upon the
  aggregate state being updated.

  ## Example

  In the example below, money is withdrawn from the bank account and the
  updated balance is used to check whether the account is overdrawn.

      defmodule BankAccount do
        alias Commanded.Aggregate.Multi

        defstruct [:account_number, :state, balance: 0]

        def withdraw(
          %BankAccount{state: :active} = account,
          %WithdrawMoney{amount: amount})
          when is_number(amount) and amount > 0
        do
          account
          |> Multi.new()
          |> Multi.execute(&withdraw_money(&1, amount))
          |> Multi.execute(&check_balance/1)
        end

        defp withdraw_money(%BankAccount{account_number: account_number, balance: balance}, amount) do
          %MoneyWithdrawn{
            account_number: account_number,
            amount: amount,
            balance: balance - amount
          }
        end

        defp check_balance(%BankAccount{account_number: account_number, balance: balance})
          when balance < 0
        do
          %AccountOverdrawn{account_number: account_number, balance: balance}
        end
        defp check_balance(%BankAccount{}), do: []
      end

  """

  alias Commanded.Aggregate.Multi

  @type t :: %__MODULE__{
          aggregate: struct(),
          executions: list(function())
        }

  defstruct [:aggregate, executions: []]

  @doc """
  Create a new `Commanded.Aggregate.Multi` struct.
  """
  @spec new(aggregate :: struct()) :: Multi.t()
  def new(aggregate), do: %Multi{aggregate: aggregate}

  @doc """
  Adds a command execute function to the multi.
  """
  @spec execute(Multi.t(), function()) :: Multi.t()
  def execute(%Multi{} = multi, execute_fun) when is_function(execute_fun, 1) do
    %Multi{executions: executions} = multi

    %Multi{multi | executions: [execute_fun | executions]}
  end

  @doc """
  Reduce an enumerable by executing the function for each item.

  The aggregate `apply/2` function will be called after each event returned by
  the execute function. This allows you to calculate values from the aggregate
  state based upon events produced by previous items in the enumerable, such as
  running totals.

  ## Example

      alias Commanded.Aggregate.Multi

      aggregate
      |> Multi.new()
      |> Multi.reduce([1, 2, 3], fn aggregate, item ->
        %AnEvent{item: item, total: aggregate.total + item}
      end)

  """
  @spec reduce(Multi.t(), Enum.t(), function()) :: Multi.t()
  def reduce(%Multi{} = multi, enumerable, execute_fun) when is_function(execute_fun, 2) do
    Enum.reduce(enumerable, multi, fn item, %Multi{} = multi ->
      execute(multi, &execute_fun.(&1, item))
    end)
  end

  @doc """
  Run the execute functions contained within the multi, returning the updated
  aggregate state and all created events.
  """
  @spec run(Multi.t()) ::
          {aggregate :: struct(), list(event :: struct())} | {:error, reason :: any()}
  def run(%Multi{aggregate: aggregate, executions: executions}) do
    try do
      executions
      |> Enum.reverse()
      |> Enum.reduce({aggregate, []}, fn execute_fun, {aggregate, events} ->
        case execute_fun.(aggregate) do
          {:error, _reason} = error ->
            throw(error)

          %Multi{} = multi ->
            Multi.run(multi)

          none when none in [:ok, nil, []] ->
            {aggregate, events}

          {:ok, pending_events} ->
            pending_events = List.wrap(pending_events)

            {apply_events(aggregate, pending_events), events ++ pending_events}

          pending_events ->
            pending_events = List.wrap(pending_events)

            {apply_events(aggregate, pending_events), events ++ pending_events}
        end
      end)
    catch
      {:error, _error} = error -> error
    end
  end

  defp apply_events(aggregate, events) do
    Enum.reduce(events, aggregate, &aggregate.__struct__.apply(&2, &1))
  end
end
