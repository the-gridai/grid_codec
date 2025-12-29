defmodule GridCodec.Types.CharArrayTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  # Define test char arrays
  defmodule Symbol8 do
    use GridCodec.Types.CharArray, length: 8
  end

  defmodule Code4 do
    use GridCodec.Types.CharArray, length: 4
  end

  defmodule StrictCode4 do
    use GridCodec.Types.CharArray, length: 4, on_overflow: :error
  end

  describe "module attributes" do
    test "length/0 returns configured length" do
      assert Symbol8.length() == 8
      assert Code4.length() == 4
    end
  end

  describe "encode/1" do
    test "exact length string" do
      binary = Symbol8.encode("ABCDEFGH")
      assert binary == "ABCDEFGH"
      assert byte_size(binary) == 8
    end

    test "shorter string is null-padded" do
      binary = Symbol8.encode("ABC")
      assert binary == <<65, 66, 67, 0, 0, 0, 0, 0>>
      assert byte_size(binary) == 8
    end

    test "longer string is truncated by default" do
      binary = Code4.encode("ABCDEFGH")
      assert binary == "ABCD"
      assert byte_size(binary) == 4
    end

    test "on_overflow: :error raises on oversized string" do
      assert_raise ArgumentError, ~r/exceeds char array length/, fn ->
        StrictCode4.encode("ABCDEFGH")
      end
    end

    test "nil encodes as all zeros" do
      binary = Symbol8.encode(nil)
      assert binary == <<0, 0, 0, 0, 0, 0, 0, 0>>
    end

    test "empty string encodes as all zeros" do
      binary = Symbol8.encode("")
      assert binary == <<0, 0, 0, 0, 0, 0, 0, 0>>
    end
  end

  describe "decode/1" do
    test "exact length string" do
      assert Symbol8.decode("ABCDEFGH") == "ABCDEFGH"
    end

    test "null-padded string has nulls stripped" do
      assert Symbol8.decode(<<65, 66, 67, 0, 0, 0, 0, 0>>) == "ABC"
    end

    test "all zeros decodes to empty string" do
      assert Symbol8.decode(<<0, 0, 0, 0, 0, 0, 0, 0>>) == ""
    end

    test "handles larger binary by taking first N bytes" do
      # If we somehow get more data, just use the first N bytes
      assert Symbol8.decode("ABCDEFGHIJKLMNOP") == "ABCDEFGH"
    end
  end

  describe "roundtrip" do
    test "encode/decode preserves exact length strings" do
      assert Symbol8.decode(Symbol8.encode("ABCDEFGH")) == "ABCDEFGH"
    end

    test "encode/decode preserves shorter strings" do
      assert Symbol8.decode(Symbol8.encode("ABC")) == "ABC"
    end

    test "encode/decode handles nil" do
      assert Symbol8.decode(Symbol8.encode(nil)) == ""
    end

    test "encode/decode handles empty string" do
      assert Symbol8.decode(Symbol8.encode("")) == ""
    end
  end

  describe "GridCodec.Type behaviour" do
    test "size/0 returns length" do
      assert Symbol8.size() == 8
      assert Code4.size() == 4
    end

    test "alignment/0 is 1" do
      assert Symbol8.alignment() == 1
      assert Code4.alignment() == 1
    end

    test "null_value/0 returns all zeros" do
      assert Symbol8.null_value() == <<0, 0, 0, 0, 0, 0, 0, 0>>
      assert Code4.null_value() == <<0, 0, 0, 0>>
    end
  end

  describe "integration with GridCodec" do
    defmodule TestCodecWithCharArray do
      use GridCodec, types: [symbol: Symbol8, code: Code4]

      defcodec do
        field :id, :u64
        field :symbol, :symbol
        field :code, :code
      end
    end

    test "encode/decode roundtrip" do
      data = %{id: 123, symbol: "BTCUSD", code: "XYZ"}
      binary = TestCodecWithCharArray.encode(data)

      # Block length: 8 (u64) + 8 (symbol) + 4 (code) = 20
      assert byte_size(binary) == 20

      {:ok, decoded} = TestCodecWithCharArray.decode(binary)
      assert decoded.id == 123
      assert decoded.symbol == "BTCUSD"
      assert decoded.code == "XYZ"
    end

    test "zero-copy access" do
      data = %{id: 456, symbol: "ETHUSD", code: "AB"}
      binary = TestCodecWithCharArray.encode(data)
      env = TestCodecWithCharArray.wrap(binary)

      assert TestCodecWithCharArray.get(env, :id) == 456
      assert TestCodecWithCharArray.get(env, :symbol) == "ETHUSD"
      assert TestCodecWithCharArray.get(env, :code) == "AB"
    end

    test "nil values encode as empty strings" do
      data = %{id: 789, symbol: nil, code: nil}
      binary = TestCodecWithCharArray.encode(data)

      {:ok, decoded} = TestCodecWithCharArray.decode(binary)
      assert decoded.symbol == ""
      assert decoded.code == ""
    end

    test "handles truncation gracefully" do
      data = %{id: 100, symbol: "VERYLONGSYMBOL", code: "TOOLONG"}
      binary = TestCodecWithCharArray.encode(data)

      {:ok, decoded} = TestCodecWithCharArray.decode(binary)
      assert decoded.symbol == "VERYLONG"
      assert decoded.code == "TOOL"
    end
  end

  describe "property tests" do
    property "roundtrip preserves strings up to length" do
      check all(
              string <- StreamData.binary(min_length: 0, max_length: 8),
              max_runs: 100
            ) do
        # Filter out null bytes for cleaner testing
        clean_string =
          string
          |> :binary.bin_to_list()
          |> Enum.filter(&(&1 != 0))
          |> :binary.list_to_bin()

        # Truncate to max length
        truncated =
          if byte_size(clean_string) > 8 do
            binary_part(clean_string, 0, 8)
          else
            clean_string
          end

        # Encode and decode
        binary = Symbol8.encode(truncated)
        decoded = Symbol8.decode(binary)

        # Decoded should match the truncated input
        assert decoded == truncated
      end
    end

    property "encoded size is always fixed length" do
      check all(
              string <- StreamData.binary(),
              max_runs: 100
            ) do
        binary = Symbol8.encode(string)
        assert byte_size(binary) == 8
      end
    end
  end
end
