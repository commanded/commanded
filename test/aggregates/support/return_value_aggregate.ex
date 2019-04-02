defmodule Commanded.Aggregates.ReturnValue do
  defmodule Command do
    defstruct [:id, :fun]
  end

  defmodule Event do
    @derive Jason.Encoder
    defstruct [:id]
  end

  defmodule ExampleAggregate do
    defstruct [:id]

    def execute(%ExampleAggregate{}, %Command{fun: fun} = command) when is_function(fun, 1) do
      %Command{fun: fun} = command

      Kernel.apply(fun, [command])
    end

    def apply(%ExampleAggregate{} = aggregate, _event), do: aggregate
  end
end
