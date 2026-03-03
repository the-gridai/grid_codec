defmodule GridCodec.MixProject do
  use Mix.Project

  @version "0.13.0"
  @source_url "https://github.com/Spectral-Finance/grid_codec"

  def project do
    [
      app: :grid_codec,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: aliases(),

      # Hex
      description: "High-performance binary codec for BEAM/Elixir with direct field access",
      package: package(),

      # Docs
      name: "GridCodec",
      docs: docs(),

      # Coverage
      test_coverage: [
        summary: [threshold: 75],
        ignore_modules: [
          # String wrapper modules that delegate to main String module
          # Their encode_ast/decode_pattern_ast/getter_ast callbacks raise
          # because they're handled specially by the compiler
          GridCodec.Types.String8,
          GridCodec.Types.String16,
          GridCodec.Types.String32,
          # Generators are dev/test utilities
          GridCodec.Generators
        ]
      ],

      # Dialyzer
      dialyzer: [
        plt_add_apps: [:mix]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  def cli do
    [
      preferred_envs: [
        "test.watch": :test,
        check: :test
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp aliases do
    [
      # Run all checks (mirrors CI)
      check: [
        "compile --warnings-as-errors",
        "format --check-formatted",
        "credo --strict",
        "test",
        "dialyzer"
      ]
    ]
  end

  defp deps do
    [
      # Runtime - Decimal type support
      {:decimal, "~> 2.0"},

      # Optional - JSON transcoder support
      {:jason, "~> 1.4", optional: true},

      # Telemetry (for instrumented encode/decode + metric definitions)
      {:telemetry, "~> 1.0"},
      {:telemetry_metrics, "~> 1.0"},

      # Dev/Test - Code quality
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:mix_test_watch, "~> 1.0", only: :test, runtime: false},
      {:stream_data, "~> 1.1", only: [:dev, :test]}
    ]
  end

  defp package do
    [
      maintainers: ["Spectral Finance"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url
      },
      files: ~w(lib docs .formatter.exs mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end

  defp docs do
    [
      main: "GridCodec",
      source_url: @source_url,
      source_ref: "v#{@version}",
      extras: [
        "README.md": [title: "Overview"],
        "docs/getting-started.md": [title: "Getting Started"],
        "docs/schemas.md": [title: "Schemas"],
        "docs/schema-evolution.md": [title: "Schema Evolution"],
        "docs/performance.md": [title: "Performance Guide"],
        "docs/troubleshooting.md": [title: "Troubleshooting"],
        "CHANGELOG.md": [title: "Changelog"],
        LICENSE: [title: "License"]
      ],
      groups_for_modules: [
        "Core DSL": [
          GridCodec,
          GridCodec.Struct
        ],
        Runtime: [
          GridCodec.Group,
          GridCodec.Dispatch,
          GridCodec.Header,
          GridCodec.Registry,
          GridCodec.BinaryInspector,
          GridCodec.Json
        ],
        Types: [
          GridCodec.Type,
          GridCodec.Types.Bool,
          GridCodec.Types.Decimal,
          GridCodec.Types.String,
          GridCodec.Types.UUID,
          GridCodec.Types.TimestampMicros,
          GridCodec.Types.TimestampNanos,
          GridCodec.Types.Enum,
          GridCodec.Types.Bitset,
          GridCodec.Types.CharArray
        ]
      ]
    ]
  end
end
