defmodule Commanded.Event.ThreeStrikesErrorHandler do
  def error({:error, :failed}, _event, %{context: context}) do
    attempts = Map.get(context, :attempts, 1)

    if attempts >= 3 do
      {:stop, :too_many}
    else
      {:retry, Map.update(context, :attempts, 1, &(&1 + 1))}
    end
  end
end
