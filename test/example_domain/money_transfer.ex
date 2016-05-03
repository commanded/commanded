defmodule Commanded.ExampleDomain.MoneyTransfer do
  use EventSourced.Entity, fields: [source_account: nil, target_account: nil, amount: 0]

  alias Commanded.ExampleDomain.MoneyTransfer

  defmodule Commands do
    defmodule TransferMoney do
      defstruct aggregate: MoneyTransfer, aggregate_uuid: UUID.uuid4, source_account: nil, target_account: nil, amount: nil
    end
  end

  defmodule Events do
    defmodule MoneyTransferRequested do
      defstruct source_account: nil, target_account: nil, amount: nil
    end
  end

  alias Events.{MoneyTransferRequested}

  def transfer_money(%MoneyTransfer{} = state, source_account, target_account, amount) when amount > 0 do
    state
    |> apply(%MoneyTransferRequested{source_account: source_account, target_account: target_account, amount: amount})
  end

  def apply(%MoneyTransfer{} = state, %MoneyTransferRequested{} = transfer_requested) do
    apply_event(state, transfer_requested, fn state -> %{state |
      source_account: transfer_requested.source_account,
      target_account: transfer_requested.target_account,
      amount: transfer_requested.amount
    } end)
  end
end
