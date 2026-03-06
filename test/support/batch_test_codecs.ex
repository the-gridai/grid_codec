defmodule GridCodec.TestSupport.Batch.SmallCommand do
  @moduledoc false
  use GridCodec.Struct, template_id: 700, schema_id: 70, version: 1

  defcodec do
    field :order_id, :u64
    field :timestamp, :u64
  end
end

defmodule GridCodec.TestSupport.Batch.MediumCommand do
  @moduledoc false
  use GridCodec.Struct, template_id: 701, schema_id: 70, version: 1

  defcodec do
    field :order_id, :u64
    field :user_id, :u64
    field :symbol, :uuid
    field :price, :u64
    field :quantity, :u32
    field :flags, :u32
  end
end

defmodule GridCodec.TestSupport.Batch.LargeCommand do
  @moduledoc false
  use GridCodec.Struct, template_id: 702, schema_id: 70, version: 1

  defcodec do
    field :order_id, :u64
    field :user_id, :u64
    field :symbol, :uuid
    field :price, :u64
    field :quantity, :u64
    field :limit_price, :u64
    field :stop_price, :u64
    field :flags, :u32
    field :side, :u8
    field :order_type, :u8
    field :time_in_force, :u8
    field :reserved, :u8
    field :timestamp, :u64
  end
end
