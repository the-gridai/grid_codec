if Code.ensure_loaded?(PromEx.Plugin) do
  defmodule GridCodec.PromEx do
    @moduledoc """
    PromEx plugin for GridCodec encode/decode metrics.

    Provides Prometheus histograms for encode and decode latency
    and byte sizes, tagged by codec `type_name`.

    ## Requirements

    - `prom_ex` must be a dependency of your application
    - Codecs must have `telemetry: true` (per-module or global config)

    ## Setup

        defmodule MyApp.PromEx do
          use PromEx, otp_app: :my_app

          @impl true
          def plugins do
            [
              PromEx.Plugins.Application,
              PromEx.Plugins.Beam,
              GridCodec.PromEx
            ]
          end

          @impl true
          def dashboards do
            [
              {:grid_codec, "grid_codec.json"}
            ]
          end
        end

    ## Metrics

    | Metric | Type | Tags | Unit |
    |--------|------|------|------|
    | `grid_codec.encode.duration.milliseconds` | distribution | `type_name` | ms |
    | `grid_codec.decode.duration.milliseconds` | distribution | `type_name` | ms |
    | `grid_codec.encode.bytes` | distribution | `type_name` | byte |
    | `grid_codec.decode.bytes` | distribution | `type_name` | byte |

    ## Options

    - `:duration_buckets` - Custom histogram buckets for duration (default: sub-millisecond to 100ms)
    - `:bytes_buckets` - Custom histogram buckets for byte sizes (default: 64B to 16MB)
    - `:metric_prefix` - Prefix for metric names (default: `:grid_codec`)
    """

    use PromEx.Plugin

    @default_duration_buckets [0.01, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10, 25, 50, 100]
    @default_bytes_buckets [64, 256, 1024, 4096, 16_384, 65_536, 262_144, 1_048_576, 16_777_216]

    @impl true
    def event_metrics(opts) do
      duration_buckets = Keyword.get(opts, :duration_buckets, @default_duration_buckets)
      bytes_buckets = Keyword.get(opts, :bytes_buckets, @default_bytes_buckets)
      prefix = Keyword.get(opts, :metric_prefix, :grid_codec)

      [
        Event.build(
          :grid_codec_encode_event_metrics,
          [
            distribution(
              [prefix, :encode, :duration, :milliseconds],
              event_name: [:grid_codec, :encode],
              measurement: :duration,
              description: "GridCodec binary encoding time per codec type.",
              reporter_options: [buckets: duration_buckets],
              tags: [:type_name],
              unit: {:native, :millisecond}
            ),
            distribution(
              [prefix, :encode, :bytes],
              event_name: [:grid_codec, :encode],
              measurement: :bytes,
              description: "GridCodec encoded binary size per codec type.",
              reporter_options: [buckets: bytes_buckets],
              tags: [:type_name],
              unit: :byte
            )
          ]
        ),
        Event.build(
          :grid_codec_decode_event_metrics,
          [
            distribution(
              [prefix, :decode, :duration, :milliseconds],
              event_name: [:grid_codec, :decode],
              measurement: :duration,
              description: "GridCodec binary decoding time per codec type.",
              reporter_options: [buckets: duration_buckets],
              tags: [:type_name],
              unit: {:native, :millisecond}
            ),
            distribution(
              [prefix, :decode, :bytes],
              event_name: [:grid_codec, :decode],
              measurement: :bytes,
              description: "GridCodec decoded binary size per codec type.",
              reporter_options: [buckets: bytes_buckets],
              tags: [:type_name],
              unit: :byte
            )
          ]
        )
      ]
    end
  end
end
