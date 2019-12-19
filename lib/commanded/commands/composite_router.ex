defmodule Commanded.Commands.CompositeRouter do
  @moduledoc """
  Composite router allows you to combine multiple router modules into a single
  router able to dispatch any registered command from an included child router.

  One example usage is to define a router per context and then combine each
  context's router into a single top-level composite app router used for all
  command dispatching.

  ### Example

  Define a composite router module which imports the commands from each included
  router:

      defmodule Bank.AppRouter do
        use Commanded.Commands.CompositeRouter

        router(Bank.Accounts.Router)
        router(Bank.MoneyTransfer.Router)
      end

  You can dispatch a command via the composite router which will be routed to
  the associated router:

      alias Bank.AppRouter

      command = %OpenAccount{account_number: "ACC123", initial_balance: 1_000}

      :ok = AppRouter.dispatch(command)

  A composite router can include composite routers.
  """

  defmacro __using__(opts) do
    quote do
      require Logger

      import unquote(__MODULE__)

      application = Keyword.get(unquote(opts), :application)

      default_dispatch_opts =
        unquote(opts)
        |> Keyword.get(:default_dispatch_opts, [])
        |> Keyword.put(:application, application)

      @default_dispatch_opts default_dispatch_opts
      @registered_commands %{}

      @before_compile unquote(__MODULE__)
    end
  end

  defmacro router(router_module) do
    quote location: :keep do
      for command <- unquote(router_module).__registered_commands__() do
        case Map.get(@registered_commands, command) do
          nil ->
            @registered_commands Map.put(@registered_commands, command, unquote(router_module))

          existing_router ->
            raise "duplicate registration for #{inspect(command)} command, registered in both #{
                    inspect(existing_router)
                  } and #{inspect(unquote(router_module))}"
        end
      end
    end
  end

  defmacro __before_compile__(_env) do
    quote generated: true do
      @doc false
      def __registered_commands__ do
        Enum.map(@registered_commands, fn {command, _router} -> command end)
      end

      def __dispatch_opts__(opts) do
        Keyword.merge(@default_dispatch_opts, opts)
      end

      @doc false
      def dispatch(command, opts \\ [])

      Enum.map(@registered_commands, fn {command_module, router} ->
        Module.eval_quoted(
          __MODULE__,
          quote do
            @doc false
            def dispatch(%unquote(command_module){} = command, :infinity) do
              opts = __dispatch_opts__(timeout: :infinity)

              unquote(router).dispatch(command, opts)
            end

            @doc false
            def dispatch(%unquote(command_module){} = command, timeout)
                when is_integer(timeout) do
              opts = __dispatch_opts__(timeout: timeout)

              unquote(router).dispatch(command, opts)
            end

            @doc false
            def dispatch(%unquote(command_module){} = command, opts) do
              opts = __dispatch_opts__(opts)

              unquote(router).dispatch(command, opts)
            end
          end
        )
      end)

      @doc false
      def dispatch(command, _opts) do
        Logger.error(fn ->
          "attempted to dispatch an unregistered command: " <> inspect(command)
        end)

        {:error, :unregistered_command}
      end
    end
  end
end
