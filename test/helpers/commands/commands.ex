defmodule Commanded.Helpers.Commands do
  @moduledoc false

  defmodule IncrementCount do
    @moduledoc false
    defstruct [aggregate_uuid: nil, by: 1]
  end

  defmodule Fail do
    @moduledoc false
    defstruct [:aggregate_uuid]
  end

  defmodule RaiseError do
    @moduledoc false
    defstruct [:aggregate_uuid]
  end

  defmodule Timeout do
    @moduledoc false
    defstruct [:aggregate_uuid]
  end

  defmodule Validate do
    @moduledoc false
    defstruct [:aggregate_uuid, :valid?]
  end

  defmodule CountIncremented do
    @moduledoc false
    defstruct [:count]
  end

  defmodule CounterAggregateRoot do
    @moduledoc false
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
    @moduledoc false
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
