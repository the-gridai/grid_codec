defmodule GridCodec.NativeBenchmarkCodec do
  @moduledoc false

  use GridCodec.Struct, template_id: 65_000, schema_id: 65_001

  defcodec do
    field :number, :u32
    field :signed, :i64
    field :active, :bool
    field :name, :string8
  end
end
