defmodule Commanded.Registration.RegisteredSupervisor do
  use DynamicSupervisor

  alias Commanded.Registration
  alias Commanded.Registration.RegisteredServer

  def start_link do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def start_child(application, name) do
    Registration.start_child(application, name, __MODULE__, {RegisteredServer, []})
  end

  def init(:ok) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
