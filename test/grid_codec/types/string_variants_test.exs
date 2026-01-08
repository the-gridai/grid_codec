defmodule GridCodec.Types.StringVariantsTest do
  @moduledoc """
  Tests that the compiler correctly uses the appropriate string variant
  (string8/string16/string32) for encoding and decoding.
  """
  use ExUnit.Case, async: true

  alias GridCodec.Envelope

  # Codec with string8 field (1-byte length prefix)
  defmodule String8Codec do
    use GridCodec.Struct

    defcodec do
      field :name, :string8
    end
  end

  # Codec with string16 field (2-byte length prefix, default)
  defmodule String16Codec do
    use GridCodec.Struct

    defcodec do
      field :name, :string16
    end
  end

  # Codec with default :string field (should be string16)
  defmodule DefaultStringCodec do
    use GridCodec.Struct

    defcodec do
      field :name, :string
    end
  end

  # Codec with string32 field (4-byte length prefix)
  defmodule String32Codec do
    use GridCodec.Struct

    defcodec do
      field :name, :string32
    end
  end

  # Codec with mixed string types
  defmodule MixedStringsCodec do
    use GridCodec.Struct

    defcodec do
      field :short_name, :string8
      field :description, :string16
      field :content, :string32
    end
  end

  describe "string8 codec" do
    test "uses 1-byte length prefix" do
      # Use header: false to get payload only for exact binary comparison
      payload = String8Codec.encode(%String8Codec{name: "hello"}, header: false)
      # string8: 1-byte prefix + data
      assert payload == <<5, "hello">>
    end

    test "nil encodes as 1-byte zero" do
      payload = String8Codec.encode(%String8Codec{name: nil}, header: false)
      assert payload == <<0>>
    end

    test "decodes correctly" do
      payload = <<5, "hello">>
      {:ok, decoded} = String8Codec.decode(payload, header: false)
      assert decoded.name == "hello"
    end

    test "roundtrip preserves value" do
      original = %String8Codec{name: "test string"}
      {:ok, decoded} = original |> String8Codec.encode() |> String8Codec.decode()
      assert decoded.name == original.name
    end
  end

  describe "string16 codec" do
    test "uses 2-byte length prefix (little-endian)" do
      payload = String16Codec.encode(%String16Codec{name: "hello"}, header: false)
      # string16: 2-byte LE prefix + data
      assert payload == <<5, 0, "hello">>
    end

    test "nil encodes as 2-byte zero" do
      payload = String16Codec.encode(%String16Codec{name: nil}, header: false)
      assert payload == <<0, 0>>
    end

    test "decodes correctly" do
      payload = <<5, 0, "hello">>
      {:ok, decoded} = String16Codec.decode(payload, header: false)
      assert decoded.name == "hello"
    end

    test "roundtrip preserves value" do
      original = %String16Codec{name: "test string"}
      {:ok, decoded} = original |> String16Codec.encode() |> String16Codec.decode()
      assert decoded.name == original.name
    end
  end

  describe "default :string type" do
    test "uses string16 encoding by default" do
      payload = DefaultStringCodec.encode(%DefaultStringCodec{name: "hello"}, header: false)
      # Should be same as string16: 2-byte LE prefix + data
      assert payload == <<5, 0, "hello">>
    end
  end

  describe "string32 codec" do
    test "uses 4-byte length prefix (little-endian)" do
      payload = String32Codec.encode(%String32Codec{name: "hello"}, header: false)
      # string32: 4-byte LE prefix + data
      assert payload == <<5, 0, 0, 0, "hello">>
    end

    test "nil encodes as 4-byte zero" do
      payload = String32Codec.encode(%String32Codec{name: nil}, header: false)
      assert payload == <<0, 0, 0, 0>>
    end

    test "decodes correctly" do
      payload = <<5, 0, 0, 0, "hello">>
      {:ok, decoded} = String32Codec.decode(payload, header: false)
      assert decoded.name == "hello"
    end

    test "roundtrip preserves value" do
      original = %String32Codec{name: "test string"}
      {:ok, decoded} = original |> String32Codec.encode() |> String32Codec.decode()
      assert decoded.name == original.name
    end
  end

  describe "mixed string types codec" do
    test "each field uses correct prefix" do
      data = %MixedStringsCodec{
        short_name: "hi",
        description: "medium",
        content: "long"
      }

      binary = MixedStringsCodec.encode(data)

      # Decode and verify
      {:ok, decoded} = MixedStringsCodec.decode(binary)
      assert decoded.short_name == "hi"
      assert decoded.description == "medium"
      assert decoded.content == "long"
    end

    test "nil values work for all types" do
      data = %MixedStringsCodec{
        short_name: nil,
        description: nil,
        content: nil
      }

      binary = MixedStringsCodec.encode(data)
      {:ok, decoded} = MixedStringsCodec.decode(binary)

      assert decoded.short_name == nil
      assert decoded.description == nil
      assert decoded.content == nil
    end

    test "mixed nil and values" do
      data = %MixedStringsCodec{
        short_name: "x",
        description: nil,
        content: "content here"
      }

      {:ok, decoded} = data |> MixedStringsCodec.encode() |> MixedStringsCodec.decode()

      assert decoded.short_name == "x"
      assert decoded.description == nil
      assert decoded.content == "content here"
    end
  end

  describe "string length limits" do
    test "string8 handles max length (255 bytes)" do
      long_string = String.duplicate("x", 255)
      data = %String8Codec{name: long_string}

      {:ok, decoded} = data |> String8Codec.encode() |> String8Codec.decode()
      assert decoded.name == long_string
    end

    test "string16 handles longer strings" do
      long_string = String.duplicate("x", 1000)
      data = %String16Codec{name: long_string}

      {:ok, decoded} = data |> String16Codec.encode() |> String16Codec.decode()
      assert decoded.name == long_string
    end

    test "string32 handles very long strings" do
      long_string = String.duplicate("x", 100_000)
      data = %String32Codec{name: long_string}

      {:ok, decoded} = data |> String32Codec.encode() |> String32Codec.decode()
      assert decoded.name == long_string
    end
  end

  describe "empty strings" do
    test "empty string8 encodes as zero-length" do
      payload = String8Codec.encode(%String8Codec{name: ""}, header: false)
      # Empty string is length 0, which is same as nil
      assert payload == <<0>>
    end

    test "empty string roundtrips as nil" do
      # GridCodec treats empty strings as nil for simplicity
      data = %String8Codec{name: ""}
      {:ok, decoded} = data |> String8Codec.encode() |> String8Codec.decode()
      assert decoded.name == nil
    end
  end

  describe "zero-copy access" do
    test "get raises for variable-length fields (strings require full decode)" do
      data = %String16Codec{name: "test value"}
      binary = String16Codec.encode(data)
      env = String16Codec.wrap(binary)

      # Variable-length fields like strings require full decode
      assert_raise ArgumentError, ~r/variable-length field/i, fn ->
        Envelope.get(env, :name)
      end
    end
  end
end
