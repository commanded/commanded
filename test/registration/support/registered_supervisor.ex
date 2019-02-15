defmodule Commanded.Registration.RegisteredSupervisor do
  use DynamicSupervisor

  alias Commanded.Registration
  alias Commanded.Registration.RegisteredServer

  def start_link do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def start_child(args) do
    DynamicSupervisor.start_child(__MODULE__, {Commanded.Registration.RegisteredServer, args})
  end

  def start_registered_child(name) do
    Registration.start_child(name, __MODULE__, [name])
  end

  def init(_) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
