defmodule GridCodec.MixProject do
  use Mix.Project

  @version "0.5.0"
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
      description: "High-performance binary codec for BEAM/Elixir with direct field access",
      package: package(),

      # Docs
      name: "GridCodec",
      docs: docs(),

      # Testing
      preferred_cli_env: [
        "test.watch": :test
      ],

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
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end

  defp docs do
    [
      main: "GridCodec",
      source_url: @source_url,
      source_ref: "v#{@version}",
      extras: [
        "README.md": [title: "Overview"],
        "CHANGELOG.md": [title: "Changelog"]
      ],
      groups_for_modules: [
        "Core DSL": [
          GridCodec,
          GridCodec.Struct
        ],
        Runtime: [
          GridCodec.Envelope,
          GridCodec.Group,
          GridCodec.Dispatch,
          GridCodec.Header,
          GridCodec.Registry
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
