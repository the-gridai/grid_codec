defmodule ExampleApp.Bench.MediumStruct do
  @moduledoc """
  Medium GridCodec struct with 32 fields (matching "small" map - flat map limit).
  """
  use GridCodec.Struct, template_id: 101, schema_id: 200

  defcodec do
    field :field_1, :u64
    field :field_2, :u64
    field :field_3, :u64
    field :field_4, :u64
    field :field_5, :u64
    field :field_6, :u64
    field :field_7, :u64
    field :field_8, :u64
    field :field_9, :u64
    field :field_10, :u64
    field :field_11, :u64
    field :field_12, :u64
    field :field_13, :u64
    field :field_14, :u64
    field :field_15, :u64
    field :field_16, :u64
    field :field_17, :u64
    field :field_18, :u64
    field :field_19, :u64
    field :field_20, :u64
    field :field_21, :u64
    field :field_22, :u64
    field :field_23, :u64
    field :field_24, :u64
    field :field_25, :u64
    field :field_26, :u64
    field :field_27, :u64
    field :field_28, :u64
    field :field_29, :u64
    field :field_30, :u64
    field :field_31, :u64
    field :field_32, :u64
  end
end
