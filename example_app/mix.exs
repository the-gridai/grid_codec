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
      aliases: aliases(),
      dialyzer: [
        plt_add_apps: [:mix]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {ExampleApp.Application, []}
    ]
  end

  def cli do
    [
      preferred_envs: [
        check: :test,
        "compile.test": :test
      ]
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
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7.18", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      bench: "run benchmarks/run_all.exs",
      "bench.quick": "run benchmarks/quick_bench.exs",
      "bench.parameterized": "run benchmarks/parameterized_bench.exs",
      "bench.validation": "run benchmarks/validation_bench.exs",
      "compile.test": "compile --warnings-as-errors",
      check: [
        "compile --warnings-as-errors",
        "format --check-formatted",
        "credo --strict",
        "test",
        "dialyzer"
      ]
    ]
  end
end
