defmodule ExampleApp.Bench.SmallStruct do
  @moduledoc """
  Small GridCodec struct with 8 fields (matching "really small" map).
  """
  use GridCodec.Struct, template_id: 100, schema_id: 200

  defcodec do
    field :field_1, :u64
    field :field_2, :u64
    field :field_3, :u64
    field :field_4, :u64
    field :field_5, :u64
    field :field_6, :u64
    field :field_7, :u64
    field :field_8, :u64
  end
end
