defmodule GridCodec.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/Spectral-Finance/grid_codec"

  def project do
    [
      app: :grid_codec,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),

      # Hex
      description: "High-performance binary codec for BEAM/Elixir with zero-copy field access",
      package: package(),

      # Docs
      name: "GridCodec",
      docs: docs(),

      # Testing
      preferred_cli_env: [
        "test.watch": :test
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Runtime - Decimal type support
      {:decimal, "~> 2.0"},

      # Dev/Test - Code quality
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:mix_test_watch, "~> 1.0", only: :test, runtime: false},
      {:stream_data, "~> 1.1", only: [:dev, :test]},

      # Benchmarking
      {:benchee, "~> 1.3", only: [:dev, :test]},
      {:benchee_html, "~> 1.0", only: [:dev, :test]},

      # Comparison codecs for benchmarks (test only)
      # Note: ETF (term_to_binary) and OTP JSON (:json) are built into OTP
      {:jason, "~> 1.4", only: [:dev, :test]},
      {:msgpax, "~> 2.4", only: [:dev, :test]},
      # Pure Elixir protobuf implementation (no protoc required)
      {:protobuf, "~> 0.15", only: [:dev, :test]},
      # ElixirProto - context-scoped schema serialization (for comparison)
      {:elixir_proto, "~> 0.1", only: [:dev, :test]}
    ]
  end

  defp package do
    [
      maintainers: ["Spectral Finance"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url
      },
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_url: @source_url,
      source_ref: "v#{@version}",
      extras: [
        "README.md",
        "CHANGELOG.md"
      ],
      groups_for_modules: [
        "Core DSL": [
          GridCodec
        ],
        "Generated Codecs": []
      ]
    ]
  end
end
