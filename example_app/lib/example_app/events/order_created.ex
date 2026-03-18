defmodule ExampleApp.Events.OrderCreated do
  @moduledoc """
  Example event codec using GridCodec.Struct with custom type modules.

  Demonstrates the recommended pattern for event sourcing: define domain
  enums as separate modules and reference them directly as field types.
  """
  use GridCodec.Struct, template_id: 1, schema_id: 100, name: "OrderCreated"

  alias ExampleApp.Types.OrderSide

  defcodec do
    field :order_id, :uuid,
      presence: :required,
      doc: "Stable identifier for the newly created order."

    field :user_id, :u64, doc: "Identifier of the user that submitted the order."
    field :symbol, :string16, doc: "Instrument symbol that the order targets."
    field :side, OrderSide, doc: "Whether the order is a bid or an ask."
    field :price, :u64, doc: "Limit price in quote units."
    field :quantity, :u32, doc: "Requested order size in base units."
    field :timestamp, :timestamp_us, doc: "Exchange timestamp when the order was accepted."
    field :flags, :u8, doc: "Compact bit flags describing order handling options."
  end
end
