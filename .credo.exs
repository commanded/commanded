%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/"],
        excluded: [~r"/_build/", ~r"/deps/", ~r"/node_modules/", ~r"/test/"]
      },
      strict: true,
      parse_timeout: 5000,
      color: true,
    }
  ]
}
