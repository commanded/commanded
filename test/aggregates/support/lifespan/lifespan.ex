defmodule Commanded.Aggregates.Lifespan do
  @behaviour Commanded.Aggregates.AggregateLifespan

  alias Commanded.Aggregates.LifespanAggregate.{Command, Event}

  def after_event(%Event{} = event) do
    %Event{reply_to: reply_to, lifespan: lifespan} = event

    reply(reply_to, :after_event)

    lifespan
  end

  def after_command(%Command{} = command) do
    %Command{reply_to: reply_to, lifespan: lifespan} = command

    reply(reply_to, :after_command)

    lifespan
  end

  def after_error({:failed, reply_to, lifespan}) do
    reply(reply_to, :after_error)

    lifespan
  end

  defp reply(nil, _msg), do: :ok

  defp reply(reply_to, msg) do
    pid = :erlang.list_to_pid(reply_to)

    send(pid, msg)
  end
end
