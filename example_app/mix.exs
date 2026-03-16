defmodule ExampleApp.MixProject do
  use Mix.Project

  def project do
    [
      app: :example_app,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      compilers: Mix.compilers() ++ [:grid_codec],
      deps: deps(),
      aliases: aliases()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {ExampleApp.Application, []}
    ]
  end

  defp deps do
    [
      # GridCodec library (path dependency)
      {:grid_codec, path: ".."},

      # JSON support (for transcoder)
      {:jason, "~> 1.4"},

      # PostgreSQL for SQL integration testing
      {:ecto_sql, "~> 3.12"},
      {:postgrex, "~> 0.19"},

      # Serialization formats for benchmarking
      {:protobuf, "~> 0.13"},
      {:msgpax, "~> 2.4"},

      # Benchmarking
      {:benchee, "~> 1.3"},

      # Docs
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},

      # Code quality
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      bench: "run benchmarks/run_all.exs",
      "bench.quick": "run benchmarks/quick_bench.exs",
      "bench.parameterized": "run benchmarks/parameterized_bench.exs",
      check: [
        "compile --warnings-as-errors",
        "format --check-formatted",
        "credo --strict"
      ]
    ]
  end
end
