defprotocol Commanded.CommandHandler do
  @doc """
  Define which aggregate applies for this command
  """
  def aggregate(command)

  @doc """
  Handle the given command, returning state struct containing the aggregate's uuid, all applied events and expected version
  """
  def handle(state, command)
end
