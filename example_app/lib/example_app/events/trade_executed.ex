defmodule ExampleApp.Events.TradeExecuted do
  @moduledoc """
  Example trade execution event with custom type modules.
  """
  use GridCodec.Struct, template_id: 2, schema_id: 100, name: "TradeExecuted"

  alias ExampleApp.Types.OrderSide

  defcodec do
    field :trade_id, :uuid
    field :order_id, :uuid
    field :side, OrderSide
    field :price, :u64
    field :quantity, :u32
    field :timestamp, :timestamp_us
  end
end
