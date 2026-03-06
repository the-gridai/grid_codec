defmodule GridCodec.Telemetry.Metrics do
  @moduledoc """
  Telemetry metric definitions for GridCodec encode/decode events.

  Returns metric specs that can be plugged into PromEx, LiveDashboard,
  or any `Telemetry.Metrics`-based consumer.

  ## Events

  When `telemetry: true` is set on a codec, these events are emitted:

  | Event | Measurements | Metadata |
  |-------|-------------|----------|
  | `[:grid_codec, :encode]` | `duration` (native), `bytes` | `module`, `type_name`, `schema_id`, `template_id` |
  | `[:grid_codec, :decode]` | `duration` (native), `bytes` | `module`, `type_name`, `schema_id`, `template_id` |

  ## PromEx Integration

  Create a plugin in your app that wraps these metrics:

      defmodule MyApp.PromEx.Plugins.GridCodec do
        use PromEx.Plugin

        @impl true
        def event_metrics(opts) do
          {encode_metrics, decode_metrics} = GridCodec.Telemetry.Metrics.prom_ex_metrics(opts)
          [encode_metrics, decode_metrics]
        end
      end

  Then add it to your PromEx module:

      def plugins do
        [
          MyApp.PromEx.Plugins.GridCodec,
          ...
        ]
      end

  ## LiveDashboard / Custom

  For non-PromEx consumers, use `metric_definitions/1` which returns
  raw `Telemetry.Metrics` structs:

      GridCodec.Telemetry.Metrics.metric_definitions()
      # => [%Telemetry.Metrics.Distribution{...}, ...]
  """

  @default_duration_buckets [0.01, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10, 25, 50, 100]
  @default_bytes_buckets [64, 256, 1024, 4096, 16_384, 65_536, 262_144, 1_048_576, 16_777_216]

  @doc """
  Returns PromEx-compatible `Event.build` tuples for encode and decode metrics.

  Requires `prom_ex` to be a dependency of your application.

  ## Options

  - `:duration_buckets` — histogram buckets for duration in ms
  - `:bytes_buckets` — histogram buckets for byte sizes
  - `:metric_prefix` — atom prefix for metric names (default: `:grid_codec`)

  ## Example

      def event_metrics(opts) do
        {encode, decode} = GridCodec.Telemetry.Metrics.prom_ex_metrics(opts)
        [encode, decode]
      end
  """
  def prom_ex_metrics(opts \\ []) do
    metrics = metric_definitions(opts)
    event_mod = Module.concat(PromEx.MetricTypes, Event)

    {encode_metrics, decode_metrics} =
      Enum.split_with(metrics, fn m ->
        m.event_name == [:grid_codec, :encode]
      end)

    encode = event_mod.build(:grid_codec_encode_event_metrics, encode_metrics)
    decode = event_mod.build(:grid_codec_decode_event_metrics, decode_metrics)

    {encode, decode}
  end

  @doc """
  Returns raw `Telemetry.Metrics` structs for use with LiveDashboard
  or any metrics consumer.

  Does NOT require PromEx.
  """
  def metric_definitions(opts \\ []) do
    duration_buckets = Keyword.get(opts, :duration_buckets, @default_duration_buckets)
    bytes_buckets = Keyword.get(opts, :bytes_buckets, @default_bytes_buckets)
    prefix = Keyword.get(opts, :metric_prefix, :grid_codec)

    [
      Telemetry.Metrics.distribution(
        "#{prefix}.encode.duration.milliseconds",
        event_name: [:grid_codec, :encode],
        measurement: :duration,
        description: "GridCodec binary encoding time per codec type.",
        reporter_options: [buckets: duration_buckets],
        tags: [:type_name],
        unit: {:native, :millisecond}
      ),
      Telemetry.Metrics.distribution(
        "#{prefix}.encode.bytes",
        event_name: [:grid_codec, :encode],
        measurement: :bytes,
        description: "GridCodec encoded binary size per codec type.",
        reporter_options: [buckets: bytes_buckets],
        tags: [:type_name],
        unit: :byte
      ),
      Telemetry.Metrics.distribution(
        "#{prefix}.decode.duration.milliseconds",
        event_name: [:grid_codec, :decode],
        measurement: :duration,
        description: "GridCodec binary decoding time per codec type.",
        reporter_options: [buckets: duration_buckets],
        tags: [:type_name],
        unit: {:native, :millisecond}
      ),
      Telemetry.Metrics.distribution(
        "#{prefix}.decode.bytes",
        event_name: [:grid_codec, :decode],
        measurement: :bytes,
        description: "GridCodec decoded binary size per codec type.",
        reporter_options: [buckets: bytes_buckets],
        tags: [:type_name],
        unit: :byte
      )
    ]
  end
end
