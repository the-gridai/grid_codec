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
    field :metric_id, :u64
    field :side, OrderSide
    field :value, :u64
    field :timestamp, :timestamp_us
  end
end
