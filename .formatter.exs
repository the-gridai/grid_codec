# Used by "mix format"
[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  locals_without_parens: [
    # GridCodec DSL
    field: 2,
    field: 3,
    group: 2,
    defcodec: 1
  ],
  export: [
    locals_without_parens: [
      field: 2,
      field: 3,
      group: 2,
      defcodec: 1
    ]
  ]
]
