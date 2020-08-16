defmodule Commanded.Registration do
  @moduledoc """
  Use the process registry configured for a Commanded application.
  """

  alias Commanded.Application

  @type application :: Commanded.Application.t()
  @type config :: Keyword.t()

  @doc false
  def supervisor_child_spec(application, module, arg) do
    {adapter, adapter_meta} = Application.registry_adapter(application)

    adapter.supervisor_child_spec(adapter_meta, module, arg)
  end

  @doc false
  def start_link(application, name, module, args, start_opts) do
    {adapter, adapter_meta} = Application.registry_adapter(application)

    if function_exported?(adapter, :start_link, 5) do
      adapter.start_link(adapter_meta, name, module, args, start_opts)
    else
      adapter.start_link(adapter_meta, name, module, args)
    end
  end

  @doc false
  def start_child(application, name, supervisor, child_spec) do
    {adapter, adapter_meta} = Application.registry_adapter(application)

    adapter.start_child(adapter_meta, name, supervisor, child_spec)
  end

  @doc false
  def whereis_name(application, name) do
    {adapter, adapter_meta} = Application.registry_adapter(application)

    adapter.whereis_name(adapter_meta, name)
  end

  @doc false
  def via_tuple(application, name) do
    {adapter, adapter_meta} = Application.registry_adapter(application)

    adapter.via_tuple(adapter_meta, name)
  end

  @doc """
  Get the configured process registry.

  Defaults to a local registry, restricted to running on a single node.
  """
  @spec adapter(application, config) :: {module, config}
  def adapter(application, config) do
    case config do
      :local ->
        {Commanded.Registration.LocalRegistry, []}

      :global ->
        {Commanded.Registration.GlobalRegistry, []}

      adapter when is_atom(adapter) ->
        {adapter, []}

      config ->
        if Keyword.keyword?(config) do
          Keyword.pop(config, :adapter)
        else
          raise ArgumentError,
                "invalid :registry option for Commanded application " <> inspect(application)
        end
    end
  end

  @doc """
  Use the `Commanded.Registration` module to import the registry adapter and
  via tuple functions.
  """
  defmacro __using__(_opts) do
    quote location: :keep do
      @before_compile unquote(__MODULE__)

      alias unquote(__MODULE__)
    end
  end

  @doc """
  Allow a registry adapter to handle the standard `GenServer` callback
  functions.
  """
  defmacro __before_compile__(_env) do
    quote generated: true, location: :keep do
      @doc false
      def handle_call(request, from, state) do
        adapter = registry_adapter(state)

        adapter.handle_call(request, from, state)
      end

      @doc false
      def handle_cast(request, state) do
        adapter = registry_adapter(state)

        adapter.handle_cast(request, state)
      end

      @doc false
      def handle_info(msg, state) do
        adapter = registry_adapter(state)

        adapter.handle_info(msg, state)
      end

      defp registry_adapter(state) do
        application = Map.get(state, :application)

        {adapter, _adapter_meta} = Application.registry_adapter(application)

        adapter
      end
    end
  end
end
