defmodule Commanded.EventStore.Subscription do
    @moduledoc """
  RecordedEvent contains the persisted data and metadata for a single event.

  Events are immutable once recorded.
  """

  @type t :: %Commanded.EventStore.Subscription{
    name: String.t,
    subscription_pid: pid,
    subscriber: pid
  }

  defstruct [
    name: nil,
    subscription_pid: nil,
    subscriber: nil
  ]
end
