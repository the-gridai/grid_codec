defmodule ExampleApp.Types.OrderSide do
  @moduledoc false
  use GridCodec.Types.Enum, encoding: :u8

  defenum do
    value(:buy)
    value(:sell)
  end
end
