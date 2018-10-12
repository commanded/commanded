# Used by "mix format"

locals_without_parens = [
  dispatch: 2,
  identify: 2,
  middleware: 1
]

[
  inputs: [
    "{mix,.formatter}.exs",
    "{config,lib,test}/**/*.{ex,exs}"
  ],
  locals_without_parens: locals_without_parens,
  export: [locals_without_parens: locals_without_parens]
]
