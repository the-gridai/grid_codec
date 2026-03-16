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
    field :trade_id, :uuid, presence: :required
    field :order_id, :uuid
    field :side, OrderSide
    field :status, OrderStatus
    field :settled_price, :u64
    field :settled_quantity, :u32
    field :timestamp, :timestamp_us
  end
end
