# Supervision

Use a supervisor to host your Commanded application, process managers, and event handlers.

```elixir
defmodule Bank.Supervisor do
  use Supervisor

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      # Application
      BankApp,

      # Event handler
      AccountBalanceHandler

      # Process manager
      TransferMoneyProcessManager,

      # Optionally, provide runtime configuration
      {WelcomeEmailHandler, start_from: :current},
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
```

Your application should start the supervisor:

```elixir
defmodule Bank do
  use Application

  def start(_type, _args) do
    Bank.Supervisor.start_link()
  end
end
```
