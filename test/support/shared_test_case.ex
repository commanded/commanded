defmodule Commanded.SharedTestCase do
  defmacro define_tests(do: block) do
    quote do
      defmacro __using__(options) do
        block = unquote(Macro.escape(block))

        quote do
          use ExUnit.Case

          @moduletag unquote(options)
          unquote(block)
        end
      end
    end
  end
end
