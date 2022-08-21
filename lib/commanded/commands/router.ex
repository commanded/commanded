defmodule Commanded.Commands.Router do
  @moduledoc """
  Command routing macro to allow configuration of each command to its command handler.

  ## Example

  Define a router module which uses `Commanded.Commands.Router` and configures
  available commands to dispatch:

      defmodule BankRouter do
        use Commanded.Commands.Router

        dispatch OpenAccount,
          to: OpenAccountHandler,
          aggregate: BankAccount,
          identity: :account_number
      end

  The `to` option determines which module receives the command being dispatched.
  This command handler module must implement a `handle/2` function. It receives
  the aggregate's state and the command to execute. Usually the command handler
  module will forward the command to the aggregate.

  Once configured, you can either dispatch a command by using the module and
  specifying the application:

      command = %OpenAccount{account_number: "ACC123", initial_balance: 1_000}

      :ok = BankRouter.dispatch(command, application: BankApp)

  Or, more simply, you should include the router module in your application:

      defmodule BankApp do
        use Commanded.Application, otp_app: :my_app

        router MyApp.Router
      end

  Then dispatch commands using the app:

      command = %OpenAccount{account_number: "ACC123", initial_balance: 1_000}

      :ok = BankApp.dispatch(command)

  ## Dispatch command directly to an aggregate

  You can route a command directly to an aggregate, without requiring an
  intermediate command handler.

  ### Example

      defmodule BankRouter do
        use Commanded.Commands.Router

        # Will route to `BankAccount.open_account/2`
        dispatch OpenAccount, to: BankAccount, identity: :account_number
      end

  By default, you must define an `execute/2` function on the aggregate module, which will be
  called with the aggregate's state and the command to execute. Using this approach, you must
  create an `execute/2` clause that pattern-matches on each command that the aggregate should
  handle.

  Alternatively, you may specify the name of a function (also receiving both the aggregate state
  and the command) on your aggregate module to which the command will be dispatched:

  ### Example

      defmodule BankRouter do
        use Commanded.Commands.Router

        # Will route to `BankAccount.open_account/2`
        dispatch OpenAccount, to: BankAccount, function: :open_account, identity: :account_number
      end

  ## Define aggregate identity

  You can define the identity field for an aggregate once using the `identify` macro.
  The configured identity will be used for all commands registered to the aggregate,
  unless overridden by a command registration.

  ### Example

      defmodule BankRouter do
        use Commanded.Commands.Router

        identify BankAccount,
          by: :account_number,
          prefix: "bank-account-"

        dispatch OpenAccount, to: BankAccount
      end

  An optional identity prefix can be used to distinguish between different
  aggregates that  would otherwise share the same identity. As an example you
  might have a `User` and a `UserPreferences` aggregate that you wish
  to share the same identity. In this scenario you should specify a `prefix`
  for each aggregate (e.g. `"user-"` and `"user-preference-"`).

  The prefix is used as the stream identity when appending and reading the
  aggregate's events: `"<identity_prefix><aggregate_uuid>"`. It can be a string or
  a zero arity function returning a string.

  ## Consistency

  You can choose the consistency guarantee when dispatching a command. The
  available options are:

    - `:eventual` (default) - don't block command dispatch while waiting for
      event handlers

          :ok = BankApp.dispatch(command)
          :ok = BankApp.dispatch(command, consistency: :eventual)

    - `:strong` - block command dispatch until all strongly
      consistent event handlers and process managers have successfully processed
      all events created by the command.

      Use this when you have event handlers that update read models you need to
      query immediately after dispatching the command.

          :ok = BankApp.dispatch(command, consistency: :strong)

    - Provide an explicit list of event handler and process manager modules (or
      their configured names), containing only those handlers you'd like to wait
      for. No other handlers will be awaited on, regardless of their own
      configured consistency setting.

      ```elixir
      :ok = BankApp.dispatch(command, consistency: [ExampleHandler, AnotherHandler])
      :ok = BankApp.dispatch(command, consistency: ["ExampleHandler", "AnotherHandler"])
      ```

      Note you cannot opt-in to strong consistency for a handler that has been
      configured as eventually consistent.

  ## Dispatch return

  By default a successful command dispatch will return `:ok`. You can change
  this behaviour by specifying a `returning` option.

  The supported options are:

    - `:aggregate_state` - to return the update aggregate state.

    - `:aggregate_version` - to return only the aggregate version.

    - `:events` - to return the resultant domain events. An empty list will be
      returned if no events were produced.

    - `:execution_result` - to return a `Commanded.Commands.ExecutionResult`
      struct containing the aggregate's identity, state, version, and any events
      produced from the command along with their associated metadata.

    - `false` - don't return anything except an `:ok`.

  ### Aggregate state

  Return the updated aggregate state as part of the dispatch result:

      {:ok, %BankAccount{}} = BankApp.dispatch(command, returning: :aggregate_state)

  This is useful when you want to immediately return fields from the aggregate's
  state without requiring an read model projection and waiting for the event(s)
  to be projected. It may also be appropriate to use this feature for unit
  tests.

  However, be warned that tightly coupling an aggregate's state with read
  requests may be harmful. It's why CQRS enforces the separation of reads from
  writes by defining two separate and specialised models.

  ### Aggregate version

  You can optionally choose to return the aggregate's version as part of the
  dispatch result:

      {:ok, aggregate_version} = BankApp.dispatch(command, returning: :aggregate_version)

  This is useful when you need to wait for an event handler, such as a read model
  projection, to be up-to-date before querying its data.

  ### Execution results

  You can also choose to return the execution result as part of the dispatch
  result:

      alias Commanded.Commands.ExecutionResult

      {:ok, %ExecutionResult{} = result} = BankApp.dispatch(command, returning: :execution_result)

  Or by setting the `default_dispatch_return` in your application config file:

      # config/config.exs
      config :commanded, default_dispatch_return: :execution_result

  Use the execution result struct to get information from the events produced
  from the command.

  ## Metadata

  You can associate metadata with all events created by the command.

  Supply a map containing key/value pairs comprising the metadata:

      :ok = BankApp.dispatch(command, metadata: %{"ip_address" => "127.0.0.1"})

  """

  alias Commanded.Commands.Router
  alias Commanded.UUID

  defmacro __using__(opts) do
    quote do
      require Logger

      import unquote(__MODULE__)

      @before_compile unquote(__MODULE__)
      @behaviour Commanded.Commands.Router

      Module.register_attribute(__MODULE__, :registered_commands, accumulate: true)
      Module.register_attribute(__MODULE__, :registered_middleware, accumulate: true)
      Module.register_attribute(__MODULE__, :registered_identities, accumulate: false)

      @default_dispatch_opts [
        application: Keyword.get(unquote(opts), :application),
        consistency: Router.get_opt(unquote(opts), :default_consistency, :eventual),
        returning: Router.get_default_dispatch_return(unquote(opts)),
        timeout: 5_000,
        lifespan: Commanded.Aggregates.DefaultLifespan,
        metadata: %{},
        retry_attempts: 10
      ]

      @default_middleware [
        Commanded.Middleware.ExtractAggregateIdentity,
        Commanded.Middleware.ConsistencyGuarantee
      ]

      @registered_identities %{}
    end
  end

  @doc """
  Include the given middleware module to be called before and after
  success or failure of each command dispatch

  The middleware module must implement the `Commanded.Middleware` behaviour.

  Middleware modules are executed in the order they are defined.

  ## Example

      defmodule BankRouter do
        use Commanded.Commands.Router

        middleware CommandLogger
        middleware MyCommandValidator
        middleware AuthorizeCommand

        dispatch [OpenAccount, DepositMoney], to: BankAccount, identity: :account_number
      end

  """
  defmacro middleware(middleware_module) do
    quote do
      @registered_middleware unquote(middleware_module)
    end
  end

  @doc """
  Define an aggregate's identity

  You can define the identity field for an aggregate using the `identify` macro.
  The configured identity will be used for all commands registered to the
  aggregate, unless overridden by a command registration.

  ## Example

      defmodule BankRouter do
        use Commanded.Commands.Router

        identify BankAccount,
          by: :account_number,
          prefix: "bank-account-"
      end

  """
  defmacro identify(aggregate_module, opts) do
    quote location: :keep, bind_quoted: [aggregate_module: aggregate_module, opts: opts] do
      case Map.get(@registered_identities, aggregate_module) do
        nil ->
          by =
            case Keyword.get(opts, :by) do
              nil ->
                raise "#{inspect(aggregate_module)} aggregate identity is missing the `by` option"

              by when is_atom(by) ->
                by

              by when is_function(by, 1) ->
                by

              invalid ->
                raise "#{inspect(aggregate_module)} aggregate identity has an invalid `by` option: #{inspect(invalid)}"
            end

          prefix =
            case Keyword.get(opts, :prefix) do
              nil ->
                nil

              prefix when is_function(prefix, 0) ->
                prefix

              prefix when is_binary(prefix) ->
                prefix

              invalid ->
                raise "#{inspect(aggregate_module)} aggregate has an invalid identity prefix: #{inspect(invalid)}"
            end

          @registered_identities Map.put(@registered_identities, aggregate_module,
                                   by: by,
                                   prefix: prefix
                                 )

        config ->
          raise "#{inspect(aggregate_module)} aggregate has already been identified by: `#{inspect(Keyword.get(config, :by))}`"
      end
    end
  end

  @doc """
  Configure the command, or list of commands, to be dispatched to the
  corresponding handler and aggregate.

  ## Example

      defmodule BankRouter do
        use Commanded.Commands.Router

        dispatch [OpenAccount, DepositMoney], to: BankAccount, identity: :account_number
      end

  """
  defmacro dispatch(command_module_or_modules, opts) do
    opts = parse_opts(opts, [])

    for command_module <- List.wrap(command_module_or_modules) do
      quote do
        if Enum.any?(@registered_commands, fn {command_module, _command_opts} ->
             command_module == unquote(command_module)
           end) do
          raise ArgumentError,
            message:
              "Command `#{inspect(unquote(command_module))}` has already been registered in router `#{inspect(__MODULE__)}`"
        end

        @registered_commands {
          unquote(command_module),
          Keyword.merge(@default_dispatch_opts, unquote(opts))
        }
      end
    end
  end

  @type dispatch_resp ::
          :ok
          | {:ok, aggregate_state :: struct()}
          | {:ok, aggregate_version :: non_neg_integer()}
          | {:ok, execution_result :: Commanded.Commands.ExecutionResult.t()}
          | {:error, :unregistered_command}
          | {:error, :consistency_timeout}
          | {:error, reason :: term()}

  @doc """
  Dispatch the given command to the registered handler.

  Returns `:ok` on success, or `{:error, reason}` on failure.

  ## Example

      command = %OpenAccount{account_number: "ACC123", initial_balance: 1_000}

      :ok = BankRouter.dispatch(command)

  """
  @callback dispatch(command :: struct()) :: dispatch_resp

  @doc """
  Dispatch the given command to the registered handler providing a timeout.

    - `command` is a command struct which must be registered with the router.

    - `timeout_or_opts` is either an integer timeout, `:infinity`, or a keyword
      list of options.

      The timeout must be an integer greater than zero which specifies how many
      milliseconds to allow the command to be handled, or the atom `:infinity`
      to wait indefinitely. The default timeout value is five seconds.

      Alternatively, an options keyword list can be provided with the following
      options.

      Options:

        - `causation_id` - an optional UUID used to identify the cause of the
          command being dispatched.

        - `command_uuid` - an optional UUID used to identify the command being
          dispatched.

        - `correlation_id` - an optional UUID used to correlate related
          commands/events together.

        - `consistency` - one of `:eventual` (default) or `:strong`. By
          setting the consistency to `:strong` a successful command dispatch
          will block until all strongly consistent event handlers and process
          managers have handled all events created by the command.

        - `metadata` - an optional map containing key/value pairs comprising
          the metadata to be associated with all events created by the
          command.

        - `returning` - to choose what response is returned from a successful
            command dispatch. The default is to return an `:ok`.

            The available options are:

            - `:aggregate_state` - to return the update aggregate state in the
              successful response: `{:ok, aggregate_state}`.

            - `:aggregate_version` - to include the aggregate stream version
              in the successful response: `{:ok, aggregate_version}`.

            - `:events` - to return the resultant domain events. An empty list
              will be returned if no events were produced.

            - `:execution_result` - to return a `Commanded.Commands.ExecutionResult`
              struct containing the aggregate's identity, version, and any
              events produced from the command along with their associated
              metadata.

            - `false` - don't return anything except an `:ok`.

        - `timeout` - as described above.

  Returns `:ok` on success unless the `:returning` option is specified where
  it returns one of `{:ok, aggregate_state}`, `{:ok, aggregate_version}`, or
  `{:ok, %Commanded.Commands.ExecutionResult{}}`.

  Returns `{:error, reason}` on failure.

  ## Example

      command = %OpenAccount{account_number: "ACC123", initial_balance: 1_000}

      :ok = BankRouter.dispatch(command, consistency: :strong, timeout: 30_000)

  """
  @callback dispatch(
              command :: struct(),
              timeout_or_opts :: non_neg_integer() | :infinity | Keyword.t()
            ) :: dispatch_resp

  defmacro __before_compile__(_env) do
    quote generated: true do
      @doc false
      def __registered_commands__ do
        Enum.map(@registered_commands, fn {command_module, _command_opts} -> command_module end)
      end

      @doc false
      def dispatch(command, opts \\ [])

      @doc false
      def dispatch(command, :infinity),
        do: do_dispatch(command, timeout: :infinity)

      @doc false
      def dispatch(command, timeout) when is_integer(timeout),
        do: do_dispatch(command, timeout: timeout)

      @doc false
      def dispatch(command, opts),
        do: do_dispatch(command, opts)

      @middleware Enum.reduce(@registered_middleware, @default_middleware, fn middleware, acc ->
                    [middleware | acc]
                  end)

      for {command_module, command_opts} <- @registered_commands do
        @aggregate Keyword.fetch!(command_opts, :aggregate)
        @handler Keyword.fetch!(command_opts, :to)
        @function Keyword.fetch!(command_opts, :function)
        @before_execute Keyword.get(command_opts, :before_execute)
        @lifespan Keyword.get(command_opts, :lifespan)
        @identity Keyword.get(command_opts, :identity)
        @identity_prefix Keyword.get(command_opts, :identity_prefix)

        @command_module command_module
        @command_opts command_opts

        defp do_dispatch(%@command_module{} = command, opts) do
          alias Commanded.Commands.Dispatcher
          alias Commanded.Commands.Dispatcher.Payload

          opts = Keyword.merge(@command_opts, opts)

          application = Keyword.fetch!(opts, :application)
          causation_id = Keyword.get(opts, :causation_id)
          command_uuid = Keyword.get_lazy(opts, :command_uuid, &UUID.uuid4/0)
          consistency = Keyword.fetch!(opts, :consistency)
          correlation_id = Keyword.get_lazy(opts, :correlation_id, &UUID.uuid4/0)
          metadata = Keyword.fetch!(opts, :metadata) |> validate_metadata()

          retry_attempts = Keyword.get(opts, :retry_attempts)
          timeout = Keyword.fetch!(opts, :timeout)

          returning =
            cond do
              Keyword.get(opts, :include_execution_result) == true ->
                :execution_result

              Keyword.get(opts, :include_aggregate_version) == true ->
                :aggregate_version

              (returning = Keyword.get(opts, :returning)) in [
                :aggregate_state,
                :aggregate_version,
                :events,
                :execution_result,
                false
              ] ->
                returning

              true ->
                false
            end

          {identity, identity_prefix} =
            case Map.get(@registered_identities, @aggregate) do
              nil ->
                {@identity, @identity_prefix}

              config ->
                identity = Keyword.get(config, :by, @identity)
                prefix = Keyword.get(config, :prefix, @identity_prefix)

                {identity, prefix}
            end

          payload = %Payload{
            application: application,
            command: command,
            command_uuid: command_uuid,
            causation_id: causation_id,
            correlation_id: correlation_id,
            consistency: consistency,
            handler_module: @handler,
            handler_function: @function,
            handler_before_execute: @before_execute,
            aggregate_module: @aggregate,
            identity: identity,
            identity_prefix: identity_prefix,
            returning: returning,
            timeout: timeout,
            lifespan: @lifespan,
            metadata: metadata,
            middleware: @middleware,
            retry_attempts: retry_attempts
          }

          Dispatcher.dispatch(payload)
        end
      end

      # Catch unregistered commands, log and return an error.
      defp do_dispatch(command, _opts) do
        Logger.error(fn ->
          "attempted to dispatch an unregistered command: " <> inspect(command)
        end)

        {:error, :unregistered_command}
      end

      # Make sure the metadata must be Map.t()
      defp validate_metadata(value) when is_map(value), do: value
      defp validate_metadata(_), do: raise(ArgumentError, message: "metadata must be an map")
    end
  end

  @doc false
  def get_opt(opts, name, default \\ nil) do
    Keyword.get(opts, name) || Application.get_env(:commanded, name) || default
  end

  @doc false
  def get_default_dispatch_return(opts) do
    cond do
      (default_dispatch_return = get_opt(opts, :default_dispatch_return)) in [
        :aggregate_state,
        :aggregate_version,
        :events,
        :execution_result,
        false
      ] ->
        default_dispatch_return

      get_opt(opts, :include_execution_result) == true ->
        :execution_result

      get_opt(opts, :include_aggregate_version) == true ->
        :aggregate_version

      true ->
        false
    end
  end

  @register_params [
    :to,
    :function,
    :before_execute,
    :aggregate,
    :identity,
    :identity_prefix,
    :timeout,
    :lifespan,
    :consistency
  ]

  defp parse_opts([{:to, aggregate_or_handler} | opts], result) do
    case Keyword.pop(opts, :aggregate) do
      {nil, opts} ->
        aggregate = aggregate_or_handler
        parse_opts(opts, [function: :execute, to: aggregate, aggregate: aggregate] ++ result)

      {aggregate, opts} ->
        handler = aggregate_or_handler
        parse_opts(opts, [function: :handle, to: handler, aggregate: aggregate] ++ result)
    end
  end

  defp parse_opts([{param, value} | opts], result) when param in @register_params do
    parse_opts(opts, [{param, value} | result])
  end

  defp parse_opts([{param, _value} | _opts], _result) do
    raise """
    unexpected dispatch parameter "#{param}"
    available params are: #{Enum.map_join(@register_params, ", ", &to_string/1)}
    """
  end

  defp parse_opts([], result), do: result
end
