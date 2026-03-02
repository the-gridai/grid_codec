defmodule ExampleApp.Events.OrderCreated do
  @moduledoc """
  Example event codec using GridCodec.Struct with custom type modules.

  Demonstrates the recommended pattern for event sourcing: define domain
  enums as separate modules and reference them directly as field types.
  """
  use GridCodec.Struct, template_id: 1, schema_id: 100, name: "OrderCreated"

  alias ExampleApp.Types.OrderSide

  defcodec do
    field :order_id, :uuid
    field :user_id, :u64
    field :symbol, :string16
    field :side, OrderSide
    field :price, :u64
    field :quantity, :u32
    field :timestamp, :timestamp_us
    field :flags, :u8
  end
end
