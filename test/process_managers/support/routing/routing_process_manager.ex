defmodule Commanded.ProcessManagers.RoutingProcessManager do
  use Commanded.ProcessManagers.ProcessManager,
    application: Commanded.MockedApp,
    name: __MODULE__

  defmodule Started do
    @enforce_keys [:process_uuid]
    defstruct [:process_uuid, :reply_to, strict?: false]
  end

  defmodule StartedFromMetadata do
    defstruct [:process_uuid, :reply_to, strict?: false]
  end

  defmodule Continued do
    @enforce_keys [:process_uuid]
    defstruct [:process_uuid, :reply_to, strict?: false]
  end

  defmodule Stopped do
    @enforce_keys [:process_uuid]
    defstruct [:process_uuid]
  end

  defmodule Errored do
    @enforce_keys [:process_uuid]
    defstruct [:process_uuid, :reply_to, :on_error]
  end

  alias Commanded.ProcessManagers.FailureContext
  alias Commanded.ProcessManagers.RoutingProcessManager

  defstruct [:processes]

  def interested?(%StartedFromMetadata{}, %{"process_uuid" => process_uuid} = _metadata),
    do: {:start, process_uuid}

  def interested?(%Started{process_uuid: process_uuid, strict?: true}),
    do: {:start!, process_uuid}

  def interested?(%Started{process_uuid: process_uuid}),
    do: {:start, process_uuid}

  def interested?(%Continued{process_uuid: process_uuid, strict?: true}),
    do: {:continue!, process_uuid}

  def interested?(%Continued{process_uuid: process_uuid}), do: {:continue, process_uuid}

  def interested?(%Stopped{process_uuid: process_uuid}), do: {:stop, process_uuid}

  def interested?(%Errored{}), do: raise("error")

  def handle(%RoutingProcessManager{}, %StartedFromMetadata{} = event) do
    %StartedFromMetadata{reply_to: reply_to} = event

    send(reply_to, {:started, self()})

    []
  end

  def handle(%RoutingProcessManager{}, %Started{} = event) do
    %Started{reply_to: reply_to} = event

    send(reply_to, {:started, self()})

    []
  end

  def handle(%RoutingProcessManager{}, %Continued{} = event) do
    %Continued{reply_to: reply_to} = event

    send(reply_to, {:continued, self()})

    []
  end

  def error({:error, error}, %Started{} = event, %FailureContext{}) do
    %Started{reply_to: reply_to} = event

    send(reply_to, {:error, error})

    {:stop, error}
  end

  def error({:error, error}, %Continued{} = event, %FailureContext{}) do
    %Continued{reply_to: reply_to} = event

    send(reply_to, {:error, error})

    {:stop, error}
  end

  def error({:error, error}, %Errored{} = event, %FailureContext{}) do
    %Errored{reply_to: reply_to, on_error: on_error} = event

    send(reply_to, {:error, error})

    on_error
  end
end
