defmodule ExampleApp.Events.TradeExecuted do
  @moduledoc """
  Example trade execution event.

  Demonstrates multiple events in the same schema namespace.
  """
  use GridCodec.Struct, template_id: 2, schema_id: 100

  defcodec do
    field :trade_id, :uuid
    field :order_id, :uuid
    field :price, :u64
    field :quantity, :u32
    field :timestamp, :timestamp_us
  end
end
