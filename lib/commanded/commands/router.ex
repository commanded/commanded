defmodule Commanded.Commands.Router do
  @moduledoc """
  Command routing macro to allow configuration of each command to its command handler.

  ## Example

      defmodule BankRouter do
        use Commanded.Commands.Router

        dispatch OpenAccount, to: OpenAccountHandler, aggregate: BankAccount, identity: :account_number
      end

      :ok = BankRouter.dispatch(%OpenAccount{account_number: "ACC123", initial_balance: 1_000})

  The command handler module must implement a `handle/2` function that receives the aggregate's state and the command to execute.
  It should delegate the command to the aggregate.

  It is also possible to route a command directly to an aggregate root. Without requiring an intermediate command handler.

  ## Example

      defmodule BankRouter do
        use Commanded.Commands.Router

        dispatch OpenAccount, to: BankAccount, identity: :account_number
      end

  The aggregate root must implement an `execute/2` function that receives the aggregate's state and the command to execute.

  """
  defmacro __using__(_) do
    quote do
      require Logger
      import unquote(__MODULE__)
      @before_compile unquote(__MODULE__)
      @registered_commands []
      @registered_middleware []
      @default_dispatch_timeout 5_000
    end
  end


  @doc """
  Include the given middleware module to be called before and after success or failure of each command dispatch

  Middleware modules are executed in the order they’ve been defined.
  """
  defmacro middleware(middleware_module) do
    quote do
      @registered_middleware @registered_middleware ++ [unquote(middleware_module)]
    end
  end

  @doc "Dispatch the given command to the corresponding handler for a given aggregate root uniquely identified"
  defmacro dispatch(command_module, opts)

  defmacro dispatch(command_modules, opts) when is_list(command_modules) do
    Enum.map(command_modules, fn command_module ->
      quote do
        dispatch(unquote(command_module), unquote(opts))
      end
    end)
  end

  # dispatch directly to the aggregate root
  defmacro dispatch(command_module, to: aggregate, identity: identity) do
    quote do
      register(unquote(command_module), to: unquote(aggregate), function: :execute, aggregate: unquote(aggregate),
        identity: unquote(identity), timeout: @default_dispatch_timeout)
    end
  end

  # dispatch directly to the aggregate root
  defmacro dispatch(command_module, to: aggregate, identity: identity, timeout: timeout) do
    quote do
      register(unquote(command_module), to: unquote(aggregate), function: :execute, aggregate: unquote(aggregate),
        identity: unquote(identity), timeout: unquote(timeout))
    end
  end

  defmacro dispatch(command_module, to: handler, aggregate: aggregate, identity: identity) do
    quote do
      register(unquote(command_module), to: unquote(handler), function: :handle, aggregate: unquote(aggregate),
        identity: unquote(identity), timeout: @default_dispatch_timeout)
    end
  end

  defmacro dispatch(command_module, to: handler, aggregate: aggregate, identity: identity, timeout: timeout) do
    quote do
      register(unquote(command_module), to: unquote(handler), function: :handle, aggregate: unquote(aggregate),
        identity: unquote(identity), timeout: unquote(timeout))
    end
  end

  defmacro register(command_module, to: handler, function: function, aggregate: aggregate, identity: identity, timeout: timeout) do
    quote do
      if Enum.member?(@registered_commands, unquote(command_module)) do
        raise "duplicate command registration for: #{inspect unquote(command_module)}"
      end

      handler_functions = unquote(handler).__info__(:functions)
      unless Keyword.get(handler_functions, unquote(function)) == 2 do
        raise "command handler #{inspect unquote(handler)} does not define a function: #{unquote(function)}/2"
      end

      @registered_commands [unquote(command_module) | @registered_commands]

      @doc """
      Dispatch the given command to the registered handler

      Returns `:ok` on success.
      """
      @spec dispatch(command :: struct) :: :ok | {:error, reason :: term}
      def dispatch(command)
      def dispatch(%unquote(command_module){} = command) do
        do_dispatch(command, unquote(timeout))
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
        do_dispatch(command, timeout)
      end

      defp do_dispatch(%unquote(command_module){} = command, timeout) do
        Commanded.Commands.Dispatcher.dispatch(%Commanded.Commands.Dispatcher.Payload{
          command: command,
          handler_module: unquote(handler),
          handler_function: unquote(function),
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
