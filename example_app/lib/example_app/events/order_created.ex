defmodule ExampleApp.Events.OrderCreated do
  @moduledoc """
  Example event codec using GridCodec.Struct.

  This demonstrates a typical event sourcing pattern where events
  are encoded/decoded for storage and transmission.
  """
  use GridCodec.Struct, template_id: 1, schema_id: 100

  defcodec do
    field :order_id, :uuid
    field :user_id, :u64
    field :symbol, :string16
    # 0 = buy, 1 = sell
    field :side, :u8
    field :price, :u64
    field :quantity, :u32
    field :timestamp, :timestamp_us
    field :flags, :u8
  end
end
