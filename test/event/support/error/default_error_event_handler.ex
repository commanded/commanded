defmodule Commanded.Event.DefaultErrorEventHandler do
  @moduledoc false

  use Commanded.Event.Handler, name: __MODULE__

  alias Commanded.ExampleDomain.BankAccount.Events.BankAccountOpened

  def handle(%BankAccountOpened{}, _metadata), do: {:error, :failed}
end
