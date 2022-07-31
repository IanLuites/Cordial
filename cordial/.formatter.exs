locals_without_parens = [
  import_schema: 1,
  import_schema: 2,
  service: 1,
  service: 2,
  rpc: 1,
  rpc: 2,
  field: 2,
  field: 3
]

[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  locals_without_parens: locals_without_parens,
  import_deps: [],
  export: [
    locals_without_parens: locals_without_parens
  ]
]
