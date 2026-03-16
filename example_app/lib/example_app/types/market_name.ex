defmodule ExampleApp.Types.MarketName do
  @moduledoc """
  Fixed-width market name field used to exercise consumer CharArray wrappers.
  """

  use GridCodec.Types.CharArray, length: 200, schema: "events"
end
