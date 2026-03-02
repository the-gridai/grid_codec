defmodule ExampleApp.Types.OrderStatus do
  @moduledoc false
  use GridCodec.Types.Enum, encoding: :u8

  defenum do
    value(:open)
    value(:filled)
    value(:cancelled)
    value(:expired)
  end
end
