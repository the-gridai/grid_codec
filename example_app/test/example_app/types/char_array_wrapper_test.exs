defmodule ExampleApp.Types.CharArrayWrapperTest do
  use ExUnit.Case, async: true

  alias ExampleApp.Types.InstrumentSymbol
  alias ExampleApp.Types.MarketName

  describe "CharArray wrapper modules" do
    test "export schema affinity metadata" do
      assert MarketName.__char_array_meta__() == %{length: 200, schema: "events"}
      assert InstrumentSymbol.__char_array_meta__() == %{length: 50, schema: "events"}
    end

    test "encode and decode fixed-width values" do
      encoded_name = MarketName.encode("Tokyo Stock Exchange")
      assert byte_size(encoded_name) == 200
      assert MarketName.decode(encoded_name) == "Tokyo Stock Exchange"

      encoded_symbol = InstrumentSymbol.encode("BTC-USD")
      assert byte_size(encoded_symbol) == 50
      assert InstrumentSymbol.decode(encoded_symbol) == "BTC-USD"
    end
  end
end
