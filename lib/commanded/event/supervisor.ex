defmodule Commanded.Event.Handler.Supervisor do
  @moduledoc false
  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts)
  end

  def child_spec(opts) do
    %{
      id: {__MODULE__, opts},
      start: {__MODULE__, :start_link, [opts]},
      restart: :permanent,
      type: :supervisor
    }
  end

  @impl Supervisor
  def init(opts) do
    concurrency = Keyword.fetch!(opts, :concurrency)

    {module, opts} = Keyword.pop(opts, :module)

    children =
      for index <- 0..(concurrency - 1) do
        opts = Keyword.put(opts, :index, index)

        %{
          id: {module, opts},
          start: {module, :start_link, [opts]},
          restart: :permanent,
          type: :worker
        }
      end

    Supervisor.init(children, strategy: :one_for_one)
  end
end
