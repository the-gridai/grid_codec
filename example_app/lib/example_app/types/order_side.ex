defmodule ExampleApp.Types.OrderSide do
  @moduledoc """
  Side of an order in the example trading domain.
  """
  use GridCodec.Types.Enum, encoding: :u8

  defenum do
    value(:buy, doc: "A buy-side order resting on or taking from the bid.")
    value(:sell, doc: "A sell-side order resting on or taking from the ask.")
  end
end
