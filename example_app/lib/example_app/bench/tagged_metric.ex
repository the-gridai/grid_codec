defmodule ExampleApp.Bench.TaggedMetric do
  @moduledoc """
  Bench struct that references OrderSide from schema 100.
  Exercises cross-schema enum import generation.
  """
  use GridCodec.Struct,
    template_id: 103,
    schema_id: 200,
    name: "ExampleApp.Bench.TaggedMetric"

  alias ExampleApp.Types.OrderSide

  defcodec do
    field :metric_id, :u64, doc: "Identifier for the benchmark metric stream."
    field :side, OrderSide, doc: "Order side carried across the cross-schema enum import."
    field :value, :u64, doc: "Observed metric value."
    field :timestamp, :timestamp_us, doc: "Timestamp when the metric sample was captured."
  end
end
