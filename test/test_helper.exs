ExUnit.start()

{:ok, _} = Commanded.Helpers.CommandAuditMiddleware.start_link()
