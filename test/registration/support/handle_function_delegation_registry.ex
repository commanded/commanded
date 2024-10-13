defmodule Commanded.Registration.HandleFunctionDelegationRegistry do
  require Logger

  @behaviour Commanded.Registration.Adapter

  @impl Commanded.Registration.Adapter
  def child_spec(application, _config) do
    registry_name = Module.concat([application, LocalRegistry])

    child_spec = [
      {Registry, keys: :unique, name: registry_name}
    ]

    {:ok, child_spec, %{registry_name: registry_name}}
  end

  @impl Commanded.Registration.Adapter
  def supervisor_child_spec(_adapter_meta, _module, _arg) do
  end

  @impl Commanded.Registration.Adapter
  def start_child(_adapter_meta, _name, _supervisor, _child_spec) do
  end

  @impl Commanded.Registration.Adapter
  def start_link(_adapter_meta, _name, _module, _args, _start_opts) do
  end

  @impl Commanded.Registration.Adapter
  def whereis_name(_adapter_meta, _name) do
  end

  @impl Commanded.Registration.Adapter
  def via_tuple(_adapter_meta, _name) do
  end

  @doc false
  def handle_call(:foo, _from, _state) do
    :bar
  end

  @doc false
  def handle_cast(:bar, _state) do
    :baz
  end

  @doc false
  def handle_info(:baz, _state) do
    :yahoo
  end
end
