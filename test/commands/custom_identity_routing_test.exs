defmodule Commanded.Commands.CustomIdentityRoutingTest do
  use Commanded.StorageCase

  alias Commanded.EventStore
  alias Commanded.ExampleDomain.BankAccount
  alias Commanded.ExampleDomain.OpenAccountHandler
  alias Commanded.ExampleDomain.BankAccount.Commands.OpenAccount

  defmodule AccountNumber do
    @derive Jason.Encoder
    defstruct [:branch, :account_number]

    defimpl String.Chars do
      def to_string(%AccountNumber{branch: branch, account_number: account_number}),
        do: branch <> ":" <> account_number
    end
  end

  defmodule CustomIdentityRouter do
    use Commanded.Commands.Router

    dispatch OpenAccount,
      to: OpenAccountHandler,
      aggregate: BankAccount,
      identity: :account_number
  end

  describe "identify aggregate using `String.Chars` protocol" do
    test "should dispatch command to aggregate instance" do
      open_account = %OpenAccount{
        account_number: %AccountNumber{branch: "B1", account_number: "ACC123"},
        initial_balance: 1_000
      }

      assert :ok = CustomIdentityRouter.dispatch(open_account)

      events = EventStore.stream_forward("B1:ACC123") |> Enum.to_list()
      assert length(events) == 1
    end
  end

  describe "invalid identity" do
    defmodule InvalidIdentity do
      @derive Jason.Encoder
      defstruct [:uuid]
    end

    test "should error" do
      open_account = %OpenAccount{
        account_number: %InvalidIdentity{},
        initial_balance: 1_000
      }

      assert {:error, {:unsupported_aggregate_identity_type, %InvalidIdentity{}}} =
               CustomIdentityRouter.dispatch(open_account)
    end
  end
end
