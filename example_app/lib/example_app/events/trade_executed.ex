defmodule ExampleApp.Events.TradeExecuted do
  @moduledoc """
  Example trade execution event with custom type modules.
  """
  use GridCodec.Struct,
    template_id: 2,
    schema_id: 100,
    name: "TradeExecuted",
    field_defaults: [presence: :required]

  alias ExampleApp.Types.OrderSide

  defcodec do
    field :trade_id, :uuid, doc: "Stable identifier for the execution."
    field :order_id, :uuid, doc: "Identifier of the order that produced the trade."
    field :side, OrderSide, doc: "Aggressor side for the executed trade."
    field :price, :u64, doc: "Execution price in quote units."
    field :quantity, :u32, doc: "Matched quantity in base units."
    field :timestamp, :timestamp_us, doc: "Timestamp when the execution occurred."
  end
end
