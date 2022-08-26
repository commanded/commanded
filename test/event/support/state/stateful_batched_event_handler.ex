defmodule Commanded.Event.StatefulBatchedEventHandler do
  use Commanded.Event.Handler,
    application: Commanded.MockedApp,
    name: __MODULE__,
    batch_size: 5

  def init(config) do
    config = Keyword.put_new(config, :state, 0)

    {:ok, config}
  end

  def handle_batch([{%{reply_to: to} = _first_event, _metadata} | _rest] = events) do
    case do_handle_batch(events, %{incremented: false}) do
      %{incremented: false} ->
        send(reply_to(to), {:batch, events})
        :ok

      acc ->
        send(reply_to(to), {:batch, events})
        {:ok, Map.get(acc, :state)}
    end
  end

  def do_handle_batch([], acc), do: acc

  def do_handle_batch([{%{reply_to: reply_to, increment: true}, metadata} | rest], acc) do
    %{state: state} = metadata
    acc_state = Map.get(acc, :state, 0)
    reply_to = :erlang.list_to_pid(reply_to)
    do_handle_batch(rest, Map.merge(acc, %{state: state + acc_state + 1, reply_to: reply_to, incremented: true}))
  end

  def do_handle_batch([{%{increment: false}, _metadata} | rest], acc),
    do: do_handle_batch(rest, acc)

  defp reply_to(to), do: :erlang.list_to_pid(to)
end
