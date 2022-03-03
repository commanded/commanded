defmodule Commanded.ExampleDomain.MoneyTransfer do
  @moduledoc false
  @derive Jason.Encoder
  defstruct transfer_uuid: nil,
            debit_account: nil,
            credit_account: nil,
            amount: 0,
            state: nil

  alias Commanded.ExampleDomain.MoneyTransfer

  defmodule Commands do
    defmodule TransferMoney do
      @derive Jason.Encoder
      defstruct(transfer_uuid: nil, debit_account: nil, credit_account: nil, amount: nil)
    end
  end

  defmodule Events do
    defmodule MoneyTransferRequested do
      @derive Jason.Encoder
      defstruct(transfer_uuid: nil, debit_account: nil, credit_account: nil, amount: nil)
    end
  end

  alias Commands.TransferMoney
  alias Events.MoneyTransferRequested

  def transfer_money(%MoneyTransfer{state: nil}, %TransferMoney{
        transfer_uuid: transfer_uuid,
        debit_account: debit_account,
        credit_account: credit_account,
        amount: amount
      })
      when amount > 0 do
    %MoneyTransferRequested{
      transfer_uuid: transfer_uuid,
      debit_account: debit_account,
      credit_account: credit_account,
      amount: amount
    }
  end

  # State mutators

  def apply(%MoneyTransfer{} = state, %MoneyTransferRequested{} = transfer_requested) do
    %MoneyTransfer{
      state
      | transfer_uuid: transfer_requested.transfer_uuid,
        debit_account: transfer_requested.debit_account,
        credit_account: transfer_requested.credit_account,
        amount: transfer_requested.amount,
        state: :requested
    }
  end
end
