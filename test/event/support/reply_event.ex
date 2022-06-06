defmodule Commanded.Event.ReplyEvent do
  @derive Jason.Encoder
  defstruct [:reply_to, :value]
end
