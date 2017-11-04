defmodule Commanded.Helpers.CompileTimeAssertions do
  @moduledoc false
  defmacro assert_compile_time_raise(expected_exception, expected_message, fun) do
    fun_quoted_at_runtime = Macro.escape(fun)

    quote do
      assert_raise unquote(expected_exception), unquote(expected_message), fn ->
        Code.eval_quoted(unquote(fun_quoted_at_runtime))
      end
    end
  end
end
