defmodule EventStore.Config do
  
  @doc """
  Normalizes the application configuration.
  """
  def parse(config) do
    {url, config} = Keyword.pop(config, :url)
    Keyword.merge(config, parse_url(url || ""))
  end

  @doc """
  Converts a database url into a Keyword list
  """
  def parse_url(""), do: []
  def parse_url(url) do
    info = url |> URI.decode() |> URI.parse()

    if is_nil(info.host) do
      raise ArgumentError, message: "host is not present"
    end

    if is_nil(info.path) or not (info.path =~ ~r"^/([^/])+$") do
      raise ArgumentError, message: "path should be a database name"
    end

    destructure [username, password], info.userinfo && String.split(info.userinfo, ":")
    "/" <> database = info.path

    opts = [username: username,
            password: password,
            database: database,
            hostname: info.host,
            port:     info.port]

    Enum.reject(opts, fn {_k, v} -> is_nil(v) end)
  end
end
