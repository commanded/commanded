defmodule Commanded.Commands.Router do
  defmacro __using__(_) do
    quote do
      require Logger
      import unquote(__MODULE__)
      @before_compile unquote(__MODULE__)
      @registered_commands []
      @registered_middleware []
    end
  end

  @doc """
  Include the given middleware module to be called before, after, and failure of each command dispatch
  """
  defmacro middleware(middleware_module) do
    quote do
      @registered_middleware @registered_middleware ++ [unquote(middleware_module)]
    end
  end

  @doc """
  Dispatch the given command to the corresponding handler for a given aggregate root uniquely identified
  """
  defmacro dispatch(command_module, opts)

  defmacro dispatch(command_modules, opts) when is_list(command_modules) do
    Enum.map(command_modules, fn command_module ->
      quote do
        dispatch(unquote(command_module), unquote(opts))
      end
    end)
  end

  defmacro dispatch(command_module, to: handler, aggregate: aggregate, identity: identity) do
    quote do
      dispatch(unquote(command_module), to: unquote(handler), aggregate: unquote(aggregate), identity: unquote(identity), timeout: 5_000)
    end
  end

  defmacro dispatch(command_module, to: handler, aggregate: aggregate, identity: identity, timeout: timeout) do
    quote do
      if Enum.member?(@registered_commands, unquote(command_module)) do
        raise "duplicate command registration for: #{unquote(command_module)}"
      end

      @registered_commands [unquote(command_module) | @registered_commands]

      @doc """
      Dispatch the given command to the registered handler

      Returns `:ok` on success.
      """
      @spec dispatch(command :: struct) :: :ok | {:error, reason :: term}
      def dispatch(command)
      def dispatch(%unquote(command_module){} = command) do
        Commanded.Commands.Dispatcher.dispatch(%Commanded.Commands.Dispatcher.Context{
          command: command,
          handler_module: unquote(handler),
          aggregate_module: unquote(aggregate),
          identity: unquote(identity),
          timeout: unquote(timeout),
          middleware: @registered_middleware,
        })
      end

      @doc """
      Dispatch the given command to the registered handler providing a timeout.

      - `timeout` is an integer greater than zero which specifies how many milliseconds to allow the command to be handled, or the atom :infinity to wait indefinitely.
        The default value is 5000.

      Returns `:ok` on success.
      """
      @spec dispatch(command :: struct, timeout :: integer | :infinity) :: :ok | {:error, reason :: term}
      def dispatch(command, timeout)
      def dispatch(%unquote(command_module){} = command, timeout) do
        Commanded.Commands.Dispatcher.dispatch(%Commanded.Commands.Dispatcher.Context{
          command: command,
          handler_module: unquote(handler),
          aggregate_module: unquote(aggregate),
          identity: unquote(identity),
          timeout: timeout,
          middleware: @registered_middleware,
        })
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
