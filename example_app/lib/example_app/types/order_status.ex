defmodule ExampleApp.Types.OrderStatus do
  @moduledoc """
  Lifecycle state for an order in the example trading domain.
  """
  use GridCodec.Types.Enum, encoding: :u8

  defenum do
    value(:open, doc: "The order is live and can still match.")
    value(:filled, doc: "The order has been fully matched.")
    value(:cancelled, doc: "The order was cancelled before full execution.")
    value(:expired, doc: "The order expired before it could fully execute.")
  end
end
