defmodule ExampleApp.Events.TradeSettled do
  @moduledoc """
  Example event using both OrderSide and OrderStatus enums.
  Exercises multi-enum export coverage.
  """
  use GridCodec.Struct,
    template_id: 4,
    schema_id: 100,
    name: "ExampleApp.Events.TradeSettled"

  alias ExampleApp.Types.OrderSide
  alias ExampleApp.Types.OrderStatus

  defcodec do
    field :trade_id, :uuid, presence: :required, doc: "Stable identifier for the settled trade."
    field :order_id, :uuid, doc: "Identifier of the order associated with the settlement."
    field :side, OrderSide, doc: "Trading side carried through from the source order."
    field :status, OrderStatus, doc: "Order status after settlement processing completes."
    field :settled_price, :u64, doc: "Final settlement price in quote units."
    field :settled_quantity, :u32, doc: "Final settled quantity in base units."
    field :timestamp, :timestamp_us, doc: "Timestamp when settlement was recorded."
  end
end
