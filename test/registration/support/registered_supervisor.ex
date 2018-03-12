defmodule Commanded.Registration.RegisteredSupervisor do
  use Supervisor

  alias Commanded.Registration
  alias Commanded.Registration.RegisteredServer

  def start_link do
    Supervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def start_child(name) do
    Registration.start_child(name, __MODULE__, [name])
  end

  def init(:ok) do
    children = [
      worker(RegisteredServer, [], restart: :temporary)
    ]

    supervise(children, strategy: :simple_one_for_one)
  end
end
