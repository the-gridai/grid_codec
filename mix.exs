defmodule GridCodec.MixProject do
  use Mix.Project

  @version "0.43.0"
  @source_url "https://github.com/Spectral-Finance/grid_codec"

  def project do
    [
      app: :grid_codec,
      version: @version,
      elixir: "~> 1.18",
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
      test_audit: [
        ignore_modules: [
          # Internal compiler assembly module; behavior is exercised through codec tests
          GridCodec.Struct.Compiler,
          # Formatting helper used by breaking-change reporting
          GridCodec.Breaking.Issue
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
        "grid_codec.test_audit",
        "test --cover",
        "dialyzer"
      ]
    ]
  end

  defp deps do
    [
      # Runtime - Decimal type support
      {:decimal, "~> 3.1"},

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
        "docs/lookups.md": [title: "Typed Groups & Lookups"],
        "docs/validations.md": [title: "Validation Pipelines"],
        "docs/schema-evolution.md": [title: "Schema Evolution"],
        "docs/binary-filtering.md": [title: "Binary Filtering & Transcoding"],
        "docs/performance.md": [title: "Performance Guide"],
        "docs/consumer-integration.md": [title: "Consumer Integration"],
        "docs/troubleshooting.md": [title: "Troubleshooting"],
        "CHANGELOG.md": [title: "Changelog"],
        LICENSE: [title: "License"]
      ],
      groups_for_modules: [
        "Core DSL": [
          GridCodec,
          GridCodec.Struct,
          GridCodec.Match,
          GridCodec.Transcoder,
          GridCodec.ValidationError,
          GridCodec.ValidationErrors,
          GridCodec.Validations
        ],
        Runtime: [
          GridCodec.Group,
          GridCodec.Lookup,
          GridCodec.View,
          GridCodec.Batch,
          GridCodec.Batch.PaddedUnion,
          GridCodec.Batch.TypedFrames,
          GridCodec.Batch.PerTypeGroups,
          GridCodec.Binary,
          GridCodec.Dispatch,
          GridCodec.Header,
          GridCodec.Registry,
          GridCodec.BinaryInspector,
          GridCodec.Json,
          GridCodec.SQL,
          GridCodec.Telemetry.Metrics,
          GridCodec.Generators
        ],
        Schema: [
          GridCodec.Schema.Parser,
          GridCodec.Schema.Formatter,
          GridCodec.Schema.Sigil
        ],
        Breaking: [
          GridCodec.Breaking.Checker,
          GridCodec.Breaking.Config,
          GridCodec.Breaking.Rules.Wire,
          GridCodec.Breaking.Rules.Source
        ],
        Types: [
          GridCodec.Type,
          GridCodec.Type.Refined,
          GridCodec.Types.U8,
          GridCodec.Types.U16,
          GridCodec.Types.U32,
          GridCodec.Types.U64,
          GridCodec.Types.I8,
          GridCodec.Types.I16,
          GridCodec.Types.I32,
          GridCodec.Types.I64,
          GridCodec.Types.F32,
          GridCodec.Types.F64,
          GridCodec.Types.Bool,
          GridCodec.Types.Decimal,
          GridCodec.Types.PositiveDecimal,
          GridCodec.Types.String,
          GridCodec.Types.String8,
          GridCodec.Types.String16,
          GridCodec.Types.String32,
          GridCodec.Types.UUID,
          GridCodec.Types.UUIDString,
          GridCodec.Types.TimestampMicros,
          GridCodec.Types.TimestampNanos,
          GridCodec.Types.DateTimeMicros,
          GridCodec.Types.DateTimeNanos,
          GridCodec.Types.Enum,
          GridCodec.Types.Bitset,
          GridCodec.Types.CharArray,
          GridCodec.Types.PrefixedId
        ]
      ]
    ]
  end
end
