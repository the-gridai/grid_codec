defmodule GridCodec.Types.StringVariantsTest do
  @moduledoc """
  Tests that the compiler correctly uses the appropriate string variant
  (string8/string16/string32) for encoding and decoding.
  """
  use ExUnit.Case, async: true

  # Codec with string8 field (1-byte length prefix)
  defmodule String8Codec do
    use GridCodec

    defcodec do
      field :name, :string8
    end
  end

  # Codec with string16 field (2-byte length prefix, default)
  defmodule String16Codec do
    use GridCodec

    defcodec do
      field :name, :string16
    end
  end

  # Codec with default :string field (should be string16)
  defmodule DefaultStringCodec do
    use GridCodec

    defcodec do
      field :name, :string
    end
  end

  # Codec with string32 field (4-byte length prefix)
  defmodule String32Codec do
    use GridCodec

    defcodec do
      field :name, :string32
    end
  end

  # Codec with mixed string types
  defmodule MixedStringsCodec do
    use GridCodec

    defcodec do
      field :short_name, :string8
      field :description, :string16
      field :content, :string32
    end
  end

  describe "string8 codec" do
    test "uses 1-byte length prefix" do
      binary = String8Codec.encode(%{name: "hello"})
      # string8: 1-byte prefix + data
      assert binary == <<5, "hello">>
    end

    test "nil encodes as 1-byte zero" do
      binary = String8Codec.encode(%{name: nil})
      assert binary == <<0>>
    end

    test "decodes correctly" do
      binary = <<5, "hello">>
      {:ok, decoded} = String8Codec.decode(binary)
      assert decoded == %{name: "hello"}
    end

    test "roundtrip preserves value" do
      original = %{name: "test string"}
      {:ok, decoded} = original |> String8Codec.encode() |> String8Codec.decode()
      assert decoded == original
    end
  end

  describe "string16 codec" do
    test "uses 2-byte length prefix (little-endian)" do
      binary = String16Codec.encode(%{name: "hello"})
      # string16: 2-byte LE prefix + data
      assert binary == <<5, 0, "hello">>
    end

    test "nil encodes as 2-byte zero" do
      binary = String16Codec.encode(%{name: nil})
      assert binary == <<0, 0>>
    end

    test "decodes correctly" do
      binary = <<5, 0, "hello">>
      {:ok, decoded} = String16Codec.decode(binary)
      assert decoded == %{name: "hello"}
    end

    test "roundtrip preserves value" do
      original = %{name: "test string"}
      {:ok, decoded} = original |> String16Codec.encode() |> String16Codec.decode()
      assert decoded == original
    end
  end

  describe "default :string type" do
    test "behaves same as string16" do
      binary_default = DefaultStringCodec.encode(%{name: "hello"})
      binary_explicit = String16Codec.encode(%{name: "hello"})
      assert binary_default == binary_explicit
    end
  end

  describe "string32 codec" do
    test "uses 4-byte length prefix (little-endian)" do
      binary = String32Codec.encode(%{name: "hello"})
      # string32: 4-byte LE prefix + data
      assert binary == <<5, 0, 0, 0, "hello">>
    end

    test "nil encodes as 4-byte zero" do
      binary = String32Codec.encode(%{name: nil})
      assert binary == <<0, 0, 0, 0>>
    end

    test "decodes correctly" do
      binary = <<5, 0, 0, 0, "hello">>
      {:ok, decoded} = String32Codec.decode(binary)
      assert decoded == %{name: "hello"}
    end

    test "roundtrip preserves value" do
      original = %{name: "test string"}
      {:ok, decoded} = original |> String32Codec.encode() |> String32Codec.decode()
      assert decoded == original
    end
  end

  describe "mixed string types codec" do
    test "encodes each field with correct prefix size" do
      data = %{
        short_name: "AB",
        description: "CD",
        content: "EF"
      }

      binary = MixedStringsCodec.encode(data)

      # short_name (string8): <<2, "AB">>
      # description (string16): <<2, 0, "CD">>
      # content (string32): <<2, 0, 0, 0, "EF">>
      expected = <<2, "AB", 2, 0, "CD", 2, 0, 0, 0, "EF">>
      assert binary == expected
    end

    test "decodes each field correctly" do
      binary = <<2, "AB", 2, 0, "CD", 2, 0, 0, 0, "EF">>
      {:ok, decoded} = MixedStringsCodec.decode(binary)

      assert decoded == %{
               short_name: "AB",
               description: "CD",
               content: "EF"
             }
    end

    test "roundtrip preserves all values" do
      original = %{
        short_name: "short",
        description: "medium description",
        content: "longer content here"
      }

      {:ok, decoded} = original |> MixedStringsCodec.encode() |> MixedStringsCodec.decode()
      assert decoded == original
    end

    test "handles nil values" do
      data = %{short_name: nil, description: nil, content: nil}
      {:ok, decoded} = data |> MixedStringsCodec.encode() |> MixedStringsCodec.decode()
      assert decoded == data
    end
  end

  describe "wire format differences" do
    test "same string has different binary sizes per variant" do
      value = "test"

      binary8 = String8Codec.encode(%{name: value})
      binary16 = String16Codec.encode(%{name: value})
      binary32 = String32Codec.encode(%{name: value})

      # string8: 1 byte prefix + 4 bytes data = 5 bytes
      assert byte_size(binary8) == 5
      # string16: 2 bytes prefix + 4 bytes data = 6 bytes
      assert byte_size(binary16) == 6
      # string32: 4 bytes prefix + 4 bytes data = 8 bytes
      assert byte_size(binary32) == 8
    end
  end
end
