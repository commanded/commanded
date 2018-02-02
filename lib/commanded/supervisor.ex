defmodule Commanded.Supervisor do
  @moduledoc false
  use Supervisor

  alias Commanded.{PubSub, Registration}

  def start_link do
    Supervisor.start_link(__MODULE__, [])
  end

  def init(_) do
    children =
      Registration.child_spec() ++ PubSub.child_spec() ++
      [
        {Task.Supervisor, name: Commanded.Commands.TaskDispatcher},
        {Commanded.Aggregates.Supervisor, []},
        {Commanded.Subscriptions, []}
      ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
