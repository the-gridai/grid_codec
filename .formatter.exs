# Used by "mix format"
[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  locals_without_parens: [
    # GridCodec DSL
    batch: 2,
    defcodec: 1,
    field: 2,
    field: 3,
    group: 2,
    lookups: 1,
    virtual: 1,
    virtual: 2
  ],
  export: [
    locals_without_parens: [
      batch: 2,
      defcodec: 1,
      field: 2,
      field: 3,
      group: 2,
      lookups: 1,
      virtual: 1,
      virtual: 2
    ]
  ]
]
