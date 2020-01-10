defmodule Commanded.ProcessManagers.IdentityProcessManager do
  @moduledoc false

  alias Commanded.DefaultApp
  alias Commanded.ProcessManagers.IdentityProcessManager
  alias Commanded.ProcessManagers.ProcessManager

  use Commanded.ProcessManagers.ProcessManager,
    application: DefaultApp,
    name: __MODULE__

  @derive Jason.Encoder
  defstruct [:uuid]

  defmodule AnEvent do
    defstruct [:uuids, :reply_to]
  end

  def interested?(%AnEvent{uuids: uuids}), do: {:start, uuids}

  def handle(%IdentityProcessManager{}, %AnEvent{} = event) do
    %AnEvent{reply_to: reply_to} = event

    uuid = ProcessManager.identity()

    send(reply_to, {:identity, uuid, self()})

    []
  end

  def apply(%IdentityProcessManager{} = state, _event), do: state
end
