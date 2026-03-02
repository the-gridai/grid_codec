defmodule GridCodec.TestSupport.OrderEvent do
  @moduledoc false
  use GridCodec.Struct, template_id: 600, schema_id: 60, name: "OrderEvent"

  alias GridCodec.TestSupport.Side
  alias GridCodec.TestSupport.Status

  defcodec do
    field :order_id, :uuid
    field :side, Side
    field :status, Status
    field :price, :u64
    field :quantity, :u32
    field :timestamp, :timestamp_us
  end
end
