defmodule Commanded.ProcessManagers.RuntimeConfigProcessManager do
  @moduledoc false

  use Commanded.ProcessManagers.ProcessManager

  alias Commanded.DefaultApp

  @derive Jason.Encoder
  defstruct [:process_uuid]

  def init(config) do
    {reply_to, config} = Keyword.pop!(config, :reply_to)
    {tenant, config} = Keyword.pop!(config, :tenant)

    config =
      config
      |> Keyword.put(:application, Module.concat([DefaultApp, tenant]))
      |> Keyword.put(:name, Module.concat([__MODULE__, tenant]))

    send(reply_to, {:init, tenant})

    {:ok, config}
  end
end
