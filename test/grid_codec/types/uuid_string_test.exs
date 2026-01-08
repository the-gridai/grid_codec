defmodule GridCodec.Types.UUIDStringTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias GridCodec.Types.UUIDString

  # Test struct for roundtrip tests
  defmodule TestStruct do
    use GridCodec.Struct, template_id: 9001

    defcodec do
      field :id, :uuid_string
      field :secondary_id, :uuid_string
    end
  end

  describe "format_uuid/1" do
    test "formats 16-byte binary to UUID string" do
      bytes = <<85, 14, 132, 0, 226, 155, 65, 212, 167, 22, 68, 102, 85, 68, 0, 0>>
      assert UUIDString.format_uuid(bytes) == "550e8400-e29b-41d4-a716-446655440000"
    end

    test "formats all zeros" do
      assert UUIDString.format_uuid(<<0::128>>) == "00000000-0000-0000-0000-000000000000"
    end

    test "formats all ones" do
      assert UUIDString.format_uuid(
               <<255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255>>
             ) ==
               "ffffffff-ffff-ffff-ffff-ffffffffffff"
    end

    test "uses lowercase hex" do
      bytes = <<171, 205, 239, 18, 52, 86, 120, 154, 188, 222, 240, 17, 35, 69, 103, 137>>
      result = UUIDString.format_uuid(bytes)
      assert result == String.downcase(result)
    end
  end

  describe "parse_uuid_string!/1" do
    test "parses standard UUID format with dashes" do
      uuid = "550e8400-e29b-41d4-a716-446655440000"
      expected = <<85, 14, 132, 0, 226, 155, 65, 212, 167, 22, 68, 102, 85, 68, 0, 0>>
      assert UUIDString.parse_uuid_string!(uuid) == expected
    end

    test "handles uppercase input" do
      uuid = "550E8400-E29B-41D4-A716-446655440000"
      expected = <<85, 14, 132, 0, 226, 155, 65, 212, 167, 22, 68, 102, 85, 68, 0, 0>>
      assert UUIDString.parse_uuid_string!(uuid) == expected
    end

    test "handles mixed case input" do
      uuid = "550e8400-E29B-41d4-A716-446655440000"
      expected = <<85, 14, 132, 0, 226, 155, 65, 212, 167, 22, 68, 102, 85, 68, 0, 0>>
      assert UUIDString.parse_uuid_string!(uuid) == expected
    end

    test "parses nil UUID" do
      uuid = "00000000-0000-0000-0000-000000000000"
      assert UUIDString.parse_uuid_string!(uuid) == <<0::128>>
    end
  end

  describe "format_uuid/1 and parse_uuid_string!/1 roundtrip" do
    test "roundtrip preserves value" do
      original = <<85, 14, 132, 0, 226, 155, 65, 212, 167, 22, 68, 102, 85, 68, 0, 0>>
      assert original |> UUIDString.format_uuid() |> UUIDString.parse_uuid_string!() == original
    end
  end

  describe "encoding" do
    test "encodes UUID string to 16 bytes" do
      data = %TestStruct{
        id: "550e8400-e29b-41d4-a716-446655440000",
        secondary_id: "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
      }

      binary = TestStruct.encode(data)
      # Header (8) + id (16) + secondary_id (16) = 40
      assert byte_size(binary) == 40
    end

    test "encodes raw 16-byte binary directly" do
      raw_uuid = <<85, 14, 132, 0, 226, 155, 65, 212, 167, 22, 68, 102, 85, 68, 0, 0>>

      data = %TestStruct{id: raw_uuid, secondary_id: raw_uuid}
      binary = TestStruct.encode(data)

      {:ok, decoded} = TestStruct.decode(binary)
      assert decoded.id == "550e8400-e29b-41d4-a716-446655440000"
    end

    test "encodes 32-char hex string (no dashes)" do
      data = %TestStruct{
        id: "550e8400e29b41d4a716446655440000",
        secondary_id: "550e8400e29b41d4a716446655440000"
      }

      binary = TestStruct.encode(data)
      {:ok, decoded} = TestStruct.decode(binary)

      assert decoded.id == "550e8400-e29b-41d4-a716-446655440000"
    end

    test "encodes nil as null UUID" do
      data = %TestStruct{id: nil, secondary_id: nil}
      binary = TestStruct.encode(data)

      {:ok, decoded} = TestStruct.decode(binary)
      assert decoded.id == nil
      assert decoded.secondary_id == nil
    end

    test "raises on invalid UUID format" do
      assert_raise ArgumentError, ~r/Invalid UUID/, fn ->
        TestStruct.encode(%TestStruct{id: "not-a-uuid", secondary_id: nil})
      end
    end

    test "raises on wrong-length binary" do
      assert_raise ArgumentError, ~r/Invalid UUID/, fn ->
        TestStruct.encode(%TestStruct{id: <<1, 2, 3>>, secondary_id: nil})
      end
    end
  end

  describe "decoding" do
    test "decodes to formatted UUID string" do
      data = %TestStruct{
        id: "550e8400-e29b-41d4-a716-446655440000",
        secondary_id: "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
      }

      binary = TestStruct.encode(data)
      {:ok, decoded} = TestStruct.decode(binary)

      assert decoded.id == "550e8400-e29b-41d4-a716-446655440000"
      assert decoded.secondary_id == "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
    end

    test "decodes null UUID as nil" do
      data = %TestStruct{id: nil, secondary_id: nil}
      binary = TestStruct.encode(data)

      {:ok, decoded} = TestStruct.decode(binary)
      assert decoded.id == nil
      assert decoded.secondary_id == nil
    end

    test "decoded value is valid UTF-8 (JSON-safe)" do
      data = %TestStruct{
        id: "550e8400-e29b-41d4-a716-446655440000",
        secondary_id: nil
      }

      binary = TestStruct.encode(data)
      {:ok, decoded} = TestStruct.decode(binary)

      assert String.valid?(decoded.id)
    end
  end

  describe "wire format" do
    test "wire format is identical to :uuid type" do
      # Both types should produce the same binary on the wire
      uuid_bytes = <<85, 14, 132, 0, 226, 155, 65, 212, 167, 22, 68, 102, 85, 68, 0, 0>>
      uuid_string = "550e8400-e29b-41d4-a716-446655440000"

      # Encode with :uuid_string type
      string_data = %TestStruct{id: uuid_string, secondary_id: nil}
      string_binary = TestStruct.encode(string_data)

      # The raw UUID bytes should be in the payload
      # Skip header (8 bytes), check first 16 bytes of payload
      <<_header::binary-size(8), payload_uuid::binary-size(16), _rest::binary>> = string_binary
      assert payload_uuid == uuid_bytes
    end
  end

  describe "get_value/3" do
    test "extracts UUID at offset as string" do
      uuid_bytes = <<85, 14, 132, 0, 226, 155, 65, 212, 167, 22, 68, 102, 85, 68, 0, 0>>
      # 5 bytes padding + 16 bytes UUID + 5 bytes padding
      binary = <<0, 0, 0, 0, 0>> <> uuid_bytes <> <<0, 0, 0, 0, 0>>

      result = UUIDString.get_value(binary, 5, :little)
      assert result == "550e8400-e29b-41d4-a716-446655440000"
    end

    test "returns nil for null UUID" do
      null_uuid = <<0::128>>
      binary = <<0, 0, 0>> <> null_uuid <> <<0, 0, 0>>

      result = UUIDString.get_value(binary, 3, :little)
      assert result == nil
    end
  end

  describe "type metadata" do
    test "size is 16 bytes" do
      assert UUIDString.size() == 16
    end

    test "alignment is 1" do
      assert UUIDString.alignment() == 1
    end

    test "null_value is 16 zero bytes" do
      assert UUIDString.null_value() == <<0::128>>
    end
  end

  describe "property tests" do
    property "roundtrip preserves UUID value" do
      check all(uuid_bytes <- binary(length: 16)) do
        # Skip null UUID as it decodes to nil
        if uuid_bytes != <<0::128>> do
          # Format and parse should roundtrip
          formatted = UUIDString.format_uuid(uuid_bytes)
          parsed = UUIDString.parse_uuid_string!(formatted)
          assert parsed == uuid_bytes
        end
      end
    end

    property "formatted UUID has correct structure" do
      check all(uuid_bytes <- binary(length: 16)) do
        if uuid_bytes != <<0::128>> do
          formatted = UUIDString.format_uuid(uuid_bytes)

          # Should be 36 characters
          assert String.length(formatted) == 36

          # Should have dashes at correct positions
          assert String.at(formatted, 8) == "-"
          assert String.at(formatted, 13) == "-"
          assert String.at(formatted, 18) == "-"
          assert String.at(formatted, 23) == "-"

          # Should only contain hex chars and dashes
          assert Regex.match?(
                   ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/,
                   formatted
                 )
        end
      end
    end

    property "encode/decode roundtrip preserves value" do
      check all(
              uuid1 <- binary(length: 16),
              uuid2 <- binary(length: 16)
            ) do
        # Use raw bytes for encoding (accepted by :uuid_string)
        data = %TestStruct{
          id: if(uuid1 == <<0::128>>, do: nil, else: uuid1),
          secondary_id: if(uuid2 == <<0::128>>, do: nil, else: uuid2)
        }

        binary = TestStruct.encode(data)
        {:ok, decoded} = TestStruct.decode(binary)

        # Compare: nil stays nil, bytes become formatted strings
        if uuid1 == <<0::128>> do
          assert decoded.id == nil
        else
          assert decoded.id == UUIDString.format_uuid(uuid1)
        end

        if uuid2 == <<0::128>> do
          assert decoded.secondary_id == nil
        else
          assert decoded.secondary_id == UUIDString.format_uuid(uuid2)
        end
      end
    end

    property "string input and bytes input produce same wire format" do
      check all(uuid_bytes <- binary(length: 16)) do
        if uuid_bytes != <<0::128>> do
          uuid_string = UUIDString.format_uuid(uuid_bytes)

          # Encode with string input
          data_string = %TestStruct{id: uuid_string, secondary_id: nil}
          binary_from_string = TestStruct.encode(data_string)

          # Encode with bytes input
          data_bytes = %TestStruct{id: uuid_bytes, secondary_id: nil}
          binary_from_bytes = TestStruct.encode(data_bytes)

          assert binary_from_string == binary_from_bytes
        end
      end
    end

    property "decoded UUID is always valid UTF-8" do
      check all(uuid_bytes <- binary(length: 16)) do
        if uuid_bytes != <<0::128>> do
          data = %TestStruct{id: uuid_bytes, secondary_id: nil}
          binary = TestStruct.encode(data)
          {:ok, decoded} = TestStruct.decode(binary)

          assert String.valid?(decoded.id)
        end
      end
    end
  end
end
