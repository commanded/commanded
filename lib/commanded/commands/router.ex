defmodule Commanded.Commands.Router do
  defmacro __using__(_) do
    quote do
      require Logger
      import unquote(__MODULE__)
      @before_compile unquote(__MODULE__)
      @registered_commands []
    end
  end

  @doc """
  Dispatch the given command to the corresponding handler for a given aggregate root uniquely identified
  """
  defmacro dispatch(command_module, opts)

  defmacro dispatch(command_modules, opts) when is_list(command_modules) do
    quote do
      unquote(command_modules)
      |> Enum.map(fn command_module -> dispatch(command_module, unquote(opts)) end)
    end
  end

  defmacro dispatch(command_module, to: handler, aggregate: aggregate, identity: identity) do
    quote do
      if Enum.member?(@registered_commands, unquote(command_module)) do
        raise "duplicate command registration for: #{unquote(command_module)}"
      end

      @registered_commands [unquote(command_module) | @registered_commands]

      @doc """
      Dispatch the given command to the registered handler

      Returns `:ok` on success.
      """
      def dispatch(command)
      def dispatch(%unquote(command_module){} = command) do
        Commanded.Commands.Dispatcher.dispatch(command, unquote(handler), unquote(aggregate), unquote(identity))
      end
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      # return error if an unregistered command is dispatched
      def dispatch(command) do
        Logger.error(fn -> "attempted to dispatch an unregistered command: #{inspect command}" end)
        {:error, :unregistered_command}
      end
    end
  end
end
