# Supervision

Use a supervisor to host your process managers and event handlers.

```elixir
defmodule Bank.Supervisor do
  use Supervisor

  def start_link do
    Supervisor.start_link(__MODULE__, :ok)
  end

  def init(:ok) do
    children = [
      # Process manager
      worker(TransferMoneyProcessManager, [[start_from: :current]]),

      # Event handler
      worker(AccountBalanceHandler, [[start_from: :origin]])
    ]

    supervise(children, strategy: :one_for_one)
  end
end
```

Your application should start the supervisor.

```elixir
defmodule Bank do
  use Application

  def start(_type, _args) do
    Bank.Supervisor.start_link()
  end
end
```
