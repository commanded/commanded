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
          executions: list({step_name :: atom(), function()})
        }

  defstruct [:aggregate, executions: []]

  @doc """
  Create a new `Commanded.Aggregate.Multi` struct.
  """
  @spec new(aggregate :: struct()) :: Multi.t()
  def new(aggregate), do: %Multi{aggregate: aggregate}

  @doc """
  Adds a command execute function to the multi.

  If `step_name` is provided, the aggregate state after that step is
  stored under that name. That can be useful in a long multi step multi
  in which one needs to know what was the agg state while procesisng
  the multi. It's possible, then, to pattern match the step name in the
  second parameter of the anonymous function to be executed.

  ## Example

      alias Commanded.Aggregate.Multi

      aggregate
      |> Multi.new()
      |> Multi.execute(:interesting_event, fn aggregate ->
        %Event{data: 1}
      end)
      |> Multi.execute(fn aggregate, %{interesting_event: aggregate_state_after_interesting_event} ->
        %Event{data: 2}
      end)
  """
  @spec execute(Multi.t(), atom(), function()) :: Multi.t()
  def execute(%Multi{} = multi, step_name \\ false, execute_fun)
      when is_function(execute_fun, 1) or is_function(execute_fun, 2) do
    %Multi{executions: executions} = multi

    %Multi{multi | executions: [{step_name, execute_fun} | executions]}
  end

  @doc """
  Reduce an enumerable by executing the function for each item.

  The aggregate `apply/2` function will be called after each event returned by
  the execute function. This allows you to calculate values from the aggregate
  state based upon events produced by previous items in the enumerable, such as
  running totals.

  If `step_name` is provided, the aggregate state after that step will be
  stored under that name. That can be useful in a long multi step multi
  in which one needs to know what was the agg state while procesisng
  the multi. It's possible, then, to pattern match the step name in the
  third parameter of the anonymous function to be executed.

  ## Examples

      alias Commanded.Aggregate.Multi

      aggregate
      |> Multi.new()
      |> Multi.reduce([1, 2, 3], fn aggregate, item ->
        %AnEvent{item: item, total: aggregate.total + item}
      end)

  ### Example with named steps

      alias Commanded.Aggregate.Multi

      aggregate
      |> Multi.new()
      |> Multi.execute(:first, fn aggregate ->
        %AnEvent{item: nil, total: 0}
      end)
      |> Multi.reduce(:second, [1, 2, 3], fn aggregate, item ->
        %AnEvent{item: item, total: aggregate.total + item}
      end)
      |> Multi.reduce([4, 5, 6], fn aggregate, item, steps ->
         %{
           first: aggregate_state_after_first_event,
           second: aggregate_state_after_second_event
         } = steps

          %AnEvent{item: item, total: aggregate.total + item}
      end)

  """
  @spec reduce(Multi.t(), atom(), Enum.t(), function()) :: Multi.t()
  def reduce(multi, step_name \\ false, enumerable, execute_fun)

  def reduce(%Multi{} = multi, step_name, enumerable, execute_fun)
      when is_function(execute_fun, 2) do
    Enum.reduce(enumerable, multi, fn item, %Multi{} = multi ->
      execute(multi, step_name, &execute_fun.(&1, item))
    end)
  end

  def reduce(%Multi{} = multi, step_name, enumerable, execute_fun)
      when is_function(execute_fun, 3) do
    Enum.reduce(enumerable, multi, fn item, %Multi{} = multi ->
      execute(multi, step_name, &execute_fun.(&1, item, &2))
    end)
  end

  @doc """
  Run the execute functions contained within the multi, returning the updated
  aggregate state, the aggregate state for each named step and all created events.
  """
  @spec run(Multi.t()) ::
          {aggregate :: struct(), list(event :: struct())} | {:error, reason :: any()}
  def run(%Multi{aggregate: aggregate, executions: executions}) do
    try do
      {evolved_aggregate, _steps, pending_events} =
        executions
        |> Enum.reverse()
        |> Enum.reduce({aggregate, %{}, []}, fn
          {step_name, execute_fun}, {aggregate, steps, events}
          when is_function(execute_fun, 1) or is_function(execute_fun, 2) ->
            case execute_function(execute_fun, aggregate, steps) do
              {:error, _reason} = error ->
                throw(error)

              %Multi{} = multi ->
                case Multi.run(multi) do
                  {:error, _reason} = error ->
                    throw(error)

                  # do not leak nested multi steps to outer multis
                  {evolved_aggregate, pending_events} ->
                    updated_steps = maybe_update_steps(step_name, steps, evolved_aggregate)

                    {evolved_aggregate, updated_steps, events ++ pending_events}
                end

              none when none in [:ok, nil, []] ->
                updated_steps = maybe_update_steps(step_name, steps, aggregate)

                {aggregate, updated_steps, events}

              {:ok, pending_events} ->
                pending_events = List.wrap(pending_events)

                evolved_aggregate = apply_events(aggregate, pending_events)

                updated_steps = maybe_update_steps(step_name, steps, evolved_aggregate)

                {evolved_aggregate, updated_steps, events ++ pending_events}

              pending_events ->
                pending_events = List.wrap(pending_events)

                evolved_aggregate = apply_events(aggregate, pending_events)

                updated_steps = maybe_update_steps(step_name, steps, evolved_aggregate)

                {evolved_aggregate, updated_steps, events ++ pending_events}
            end
        end)

      {evolved_aggregate, pending_events}
    catch
      {:error, _error} = error -> error
    end
  end

  defp maybe_update_steps(step_name, actual_steps, aggregate_state_after_step)

  defp maybe_update_steps(false, actual_steps, _aggregate_state_after_step), do: actual_steps

  defp maybe_update_steps(step_name, actual_steps, aggregate_state_after_step) do
    Map.put(actual_steps, step_name, aggregate_state_after_step)
  end

  defp execute_function(execute_fun, aggregate, _steps)
       when is_function(execute_fun, 1) do
    execute_fun.(aggregate)
  end

  defp execute_function(execute_fun, aggregate, steps)
       when is_function(execute_fun, 2) do
    execute_fun.(aggregate, steps)
  end

  defp apply_events(aggregate, events) do
    Enum.reduce(events, aggregate, &aggregate.__struct__.apply(&2, &1))
  end
end
