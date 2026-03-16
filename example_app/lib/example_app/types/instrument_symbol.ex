defmodule ExampleApp.Types.InstrumentSymbol do
  @moduledoc """
  Fixed-width instrument symbol field used to exercise consumer CharArray wrappers.
  """

  use GridCodec.Types.CharArray, length: 50, schema: "events"
end
