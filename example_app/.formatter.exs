[
  import_deps: [:grid_codec],
  inputs: [
    "{mix,.formatter}.exs",
    "{config,lib,test}/**/*.{ex,exs}",
    "benchmarks/sql_generation_bench.exs",
    "priv/sql_integration_test.exs"
  ]
]
