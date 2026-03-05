defmodule GridCodec.TelemetryMetricsTest do
  use ExUnit.Case, async: true

  alias GridCodec.Telemetry.Metrics

  describe "metric_definitions/1" do
    test "returns 4 distribution metrics" do
      metrics = Metrics.metric_definitions()
      assert length(metrics) == 4
      assert Enum.all?(metrics, &match?(%Telemetry.Metrics.Distribution{}, &1))
    end

    test "includes encode duration and bytes metrics" do
      metrics = Metrics.metric_definitions()
      names = Enum.map(metrics, & &1.name)

      assert [:grid_codec, :encode, :duration, :milliseconds] in names
      assert [:grid_codec, :encode, :bytes] in names
    end

    test "includes decode duration and bytes metrics" do
      metrics = Metrics.metric_definitions()
      names = Enum.map(metrics, & &1.name)

      assert [:grid_codec, :decode, :duration, :milliseconds] in names
      assert [:grid_codec, :decode, :bytes] in names
    end

    test "all metrics tag by :type_name" do
      metrics = Metrics.metric_definitions()
      assert Enum.all?(metrics, fn m -> :type_name in m.tags end)
    end

    test "custom metric_prefix" do
      metrics = Metrics.metric_definitions(metric_prefix: :my_app)
      names = Enum.map(metrics, & &1.name)

      assert [:my_app, :encode, :duration, :milliseconds] in names
      assert [:my_app, :decode, :bytes] in names
    end

    test "custom duration_buckets" do
      buckets = [1, 5, 10]
      metrics = Metrics.metric_definitions(duration_buckets: buckets)

      duration_metric =
        Enum.find(metrics, fn m -> m.name == [:grid_codec, :encode, :duration, :milliseconds] end)

      assert duration_metric.reporter_options[:buckets] == buckets
    end

    test "custom bytes_buckets" do
      buckets = [100, 1000]
      metrics = Metrics.metric_definitions(bytes_buckets: buckets)

      bytes_metric =
        Enum.find(metrics, fn m -> m.name == [:grid_codec, :encode, :bytes] end)

      assert bytes_metric.reporter_options[:buckets] == buckets
    end

    test "encode metrics listen to [:grid_codec, :encode] event" do
      metrics = Metrics.metric_definitions()

      encode_metrics =
        Enum.filter(metrics, fn m -> :encode in m.name end)

      assert length(encode_metrics) == 2

      assert Enum.all?(encode_metrics, fn m ->
               m.event_name == [:grid_codec, :encode]
             end)
    end

    test "decode metrics listen to [:grid_codec, :decode] event" do
      metrics = Metrics.metric_definitions()

      decode_metrics =
        Enum.filter(metrics, fn m -> :decode in m.name end)

      assert length(decode_metrics) == 2

      assert Enum.all?(decode_metrics, fn m ->
               m.event_name == [:grid_codec, :decode]
             end)
    end
  end
end
