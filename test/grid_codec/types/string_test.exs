defmodule GridCodec.Types.StringTest do
  use ExUnit.Case
  use ExUnitProperties

  alias GridCodec.Types.String, as: StringType
  alias GridCodec.Generators

  describe "encode/1" do
    test "encodes nil as zero-length" do
      assert StringType.encode(nil) == <<0, 0>>
    end

    test "encodes empty string as zero-length" do
      assert StringType.encode("") == <<0, 0>>
    end

    test "encodes string with length prefix" do
      assert StringType.encode("hello") == <<5, 0, "hello">>
    end

    test "encodes UTF-8 string" do
      # "café" is 5 bytes in UTF-8
      binary = StringType.encode("café")
      assert <<5, 0, "café">> = binary
    end

    test "raises on string exceeding max length" do
      large_string = String.duplicate("x", 70_000)

      assert_raise ArgumentError, ~r/exceeds u16 max/, fn ->
        StringType.encode(large_string)
      end
    end
  end

  describe "decode/1" do
    test "decodes nil (zero-length)" do
      {value, rest} = StringType.decode(<<0, 0, "rest">>)
      assert value == nil
      assert rest == "rest"
    end

    test "decodes string with rest" do
      {value, rest} = StringType.decode(<<5, 0, "hello", "world">>)
      assert value == "hello"
      assert rest == "world"
    end

    test "decodes UTF-8 string" do
      binary = <<5, 0, "café", "!">>
      {value, rest} = StringType.decode(binary)
      assert value == "café"
      assert rest == "!"
    end

    test "raises on insufficient data" do
      assert_raise ArgumentError, ~r/Insufficient data/, fn ->
        StringType.decode(<<100, 0, "short">>)
      end
    end
  end

  describe "roundtrip" do
    test "encode then decode returns original" do
      strings = [
        "hello",
        "",
        nil,
        "hello world",
        "café ☕",
        String.duplicate("x", 1000)
      ]

      for str <- strings do
        binary = StringType.encode(str)
        {decoded, ""} = StringType.decode(binary)

        if str == "" do
          # Empty string decodes as nil
          assert decoded == nil
        else
          assert decoded == str
        end
      end
    end

    test "multiple strings in sequence" do
      s1 = StringType.encode("first")
      s2 = StringType.encode("second")
      s3 = StringType.encode("third")
      binary = <<s1::binary, s2::binary, s3::binary>>

      {v1, rest1} = StringType.decode(binary)
      {v2, rest2} = StringType.decode(rest1)
      {v3, rest3} = StringType.decode(rest2)

      assert v1 == "first"
      assert v2 == "second"
      assert v3 == "third"
      assert rest3 == ""
    end
  end

  describe "type behaviour" do
    test "size returns :variable" do
      assert StringType.size() == :variable
    end

    test "alignment returns 1" do
      assert StringType.alignment() == 1
    end

    test "null_value returns nil" do
      assert StringType.null_value() == nil
    end

    test "max_length returns 65535" do
      assert StringType.max_length() == 65_535
    end
  end

  # ============================================================================
  # Property-Based Tests
  # ============================================================================

  describe "property: string roundtrip" do
    property "string16 encode/decode roundtrip" do
      check all(str <- Generators.string16(), max_runs: 100) do
        binary = StringType.encode16(str)
        {decoded, ""} = StringType.decode16(binary)

        if str == "" do
          assert decoded == nil
        else
          assert decoded == str
        end
      end
    end

    property "string8 encode/decode roundtrip" do
      check all(str <- Generators.string8(), max_runs: 100) do
        binary = StringType.encode8(str)
        {decoded, ""} = StringType.decode8(binary)

        if str == "" do
          assert decoded == nil
        else
          assert decoded == str
        end
      end
    end

    property "length prefix is accurate" do
      check all(str <- Generators.string16(), max_runs: 50) do
        binary = StringType.encode16(str)
        <<len::little-16, _rest::binary>> = binary
        assert len == byte_size(str)
      end
    end
  end
end
