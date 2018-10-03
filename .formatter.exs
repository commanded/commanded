locals_without_parens = [
  dispatch: 2,
  identify: 2,
  middleware: 1
]

[
  inputs: [
    "lib/*/{lib,test}/**/*.{ex,exs}",
    "lib/*/mix.exs"
  ],
  locals_without_parens: locals_without_parens,
  export: [locals_without_parens: locals_without_parens]
]
