defmodule ExampleApp.MixProject do
  use Mix.Project

  def project do
    [
      app: :example_app,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      # GridCodec library (path dependency)
      {:grid_codec, path: ".."},

      # Benchmarking
      {:benchee, "~> 1.3"}
    ]
  end

  defp aliases do
    [
      bench: "run benchmarks/run_all.exs",
      "bench.quick": "run benchmarks/quick_bench.exs",
      "bench.parameterized": "run benchmarks/parameterized_bench.exs"
    ]
  end
end
