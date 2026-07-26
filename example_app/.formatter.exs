[
  import_deps: [:grid_codec],
  inputs: [
    "{mix,.formatter}.exs",
    "{config,lib,test}/**/*.{ex,exs}",
    "benchmarks/sql_decode_bench.exs",
    "priv/sql_decoder_evolution_test.exs",
    "priv/sql_integration_test.exs"
  ]
]
