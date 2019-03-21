defmodule Commanded.Event.Upcast.UpcastAggregate do
  @moduledoc false
  defstruct [:id]

  alias Commanded.Event.Upcast.UpcastAggregate
  alias Commanded.Event.Upcast.Events.EventFour

  def apply(%UpcastAggregate{} = aggregate, %EventFour{} = event) do
    %EventFour{reply_to: reply_to} = event

    send(:erlang.list_to_pid(reply_to), event)

    aggregate
  end
end
