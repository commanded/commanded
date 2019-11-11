defmodule Commanded.Registration.RegisteredServer do
  use GenServer
  use Commanded.Registration

  def start_link(args) do
    name = args[:name]

    GenServer.start_link(__MODULE__, name, name: name)
  end

  def init(name), do: {:ok, name}
end
