defmodule Commanded.Event.Upcast.UpcastAggregate do
  @moduledoc false
  defstruct [:id]

  alias Commanded.Event.Upcast.Events.EventFour
  alias Commanded.Event.Upcast.UpcastAggregate

  def apply(%UpcastAggregate{} = aggregate, %EventFour{} = event) do
    %EventFour{reply_to: reply_to} = event

    send(:erlang.list_to_pid(reply_to), event)

    aggregate
  end
end
