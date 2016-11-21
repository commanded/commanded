defmodule Commanded.Helpers.Commands do
  defmodule IncrementCount do
    defstruct [aggregate_uuid: nil, by: 1]
  end

  defmodule Fail, do: defstruct [:aggregate_uuid]
  defmodule RaiseError, do: defstruct [:aggregate_uuid]
  defmodule Timeout, do: defstruct [:aggregate_uuid]
  defmodule Validate, do: defstruct [:aggregate_uuid, :valid?]
  defmodule CountIncremented, do: defstruct [:count]

  defmodule CounterAggregateRoot do
    defstruct [count: 0]

    def increment(%CounterAggregateRoot{count: count}, increment_by)
      when is_integer(increment_by)
    do
      %CountIncremented{count: count + increment_by}
    end

    def apply(%CounterAggregateRoot{} = state, %CountIncremented{count: count}) do
      %CounterAggregateRoot{state | count: count}
    end
  end

  defmodule CommandHandler do
    @behaviour Commanded.Commands.Handler

    def handle(%CounterAggregateRoot{} = aggregate, %IncrementCount{by: by}) do
      CounterAggregateRoot.increment(aggregate, by)
    end

    def handle(%CounterAggregateRoot{}, %Fail{}) do
      {:error, :failed}
    end

    def handle(%CounterAggregateRoot{}, %RaiseError{}) do
      raise "failed"
    end

    def handle(%CounterAggregateRoot{}, %Timeout{}) do
      :timer.sleep 1_000
      []
    end

    def handle(%CounterAggregateRoot{}, %Validate{}) do
      []
    end
  end
end
