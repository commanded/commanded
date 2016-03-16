defmodule EventStore.Storage.Database do
  require Logger

  alias EventStore.Storage
  
  def create(config) do
    database = Keyword.fetch!(config, :database)
    encoding = Keyword.get(config, :encoding, "UTF8")

    {output, status} = run_with_psql(config, "CREATE DATABASE \"#{database}\" ENCODING='#{encoding}'")

    cond do
      status == 0                       -> :ok
      String.contains?(output, "42P04") -> {:error, :already_up}
      true                              -> {:error, output}
    end
  end

  def drop(config) do
    database = Keyword.fetch!(config, :database)

    {output, status} = run_with_psql(config, "DROP DATABASE \"#{database}\"")

    cond do
      status == 0                       -> :ok
      String.contains?(output, "3D000") -> {:error, :already_down}
      true                              -> {:error, output}
    end
  end

  defp run_with_psql(config, sql_command) do
    unless System.find_executable("psql") do
      raise "could not find executable `psql` in path, " <>
            "please guarantee it is available before running event_store mix commands"
    end

    env =
      if password = config[:password] do
        [{"PGPASSWORD", password}]
      else
        []
      end
    env = [{"PGCONNECT_TIMEOUT", "10"} | env]

    args = []

    if username = config[:username] do
      args = ["-U", username|args]
    end

    if port = config[:port] do
      args = ["-p", to_string(port)|args]
    end

    host = config[:hostname] || System.get_env("PGHOST") || "localhost"
    args = args ++ ["--quiet",
                    "--host", host,
                    "--no-password",
                    "--set", "ON_ERROR_STOP=1",
                    "--set", "VERBOSITY=verbose",
                    "--no-psqlrc",
                    "-d", "template1",
                    "-c", sql_command]
    System.cmd("psql", args, env: env, stderr_to_stdout: true)
  end
end
