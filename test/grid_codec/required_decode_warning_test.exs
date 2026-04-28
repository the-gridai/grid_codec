defmodule GridCodec.RequiredDecodeWarningTest do
  use ExUnit.Case, async: true

  alias GridCodec.TestSupport.RequiredDecodeDefaultOnlyFixture
  alias GridCodec.TestSupport.RequiredDecodeMixedDefaultFixture
  alias GridCodec.TestSupport.RequiredDecodeWarningFixture
  alias GridCodec.TestSupport.RequiredDecodeWarningOptionalWriter

  @raw_uuid <<0x55, 0x0E, 0x84, 0x00, 0xE2, 0x9B, 0x41, 0xD4, 0xA7, 0x16, 0x44, 0x66, 0x55, 0x44,
              0x00, 0x00>>
  @uuid_text "550e8400-e29b-41d4-a716-446655440000"

  test "required nullable built-in fields round-trip without nil values" do
    orig = %RequiredDecodeWarningFixture{
      id: 7,
      raw_uuid: @raw_uuid,
      uuid_text: @uuid_text,
      string_default: "default",
      short_text: "short",
      medium_text: "medium",
      long_text: "long"
    }

    assert {:ok, bin} = RequiredDecodeWarningFixture.encode(orig)
    assert {:ok, decoded} = RequiredDecodeWarningFixture.decode(bin)

    assert decoded.id == 7
    assert decoded.raw_uuid == @raw_uuid
    assert decoded.uuid_text == @uuid_text
    assert decoded.string_default == "default"
    assert decoded.short_text == "short"
    assert decoded.medium_text == "medium"
    assert decoded.long_text == "long"
  end

  test "required uuid_string still rejects the null sentinel" do
    orig = %RequiredDecodeWarningOptionalWriter{
      id: 1,
      raw_uuid: @raw_uuid,
      uuid_text: nil,
      string_default: "default",
      short_text: "short",
      medium_text: "medium",
      long_text: "long"
    }

    assert {:ok, bin} = RequiredDecodeWarningOptionalWriter.encode(orig, header: false)

    assert {:error, {:required_field_absent, :uuid_text}} =
             RequiredDecodeWarningFixture.decode(bin, header: false)
  end

  test "required string16 still rejects the nil sentinel" do
    orig = %RequiredDecodeWarningOptionalWriter{
      id: 1,
      raw_uuid: @raw_uuid,
      uuid_text: @uuid_text,
      string_default: "default",
      short_text: "short",
      medium_text: nil,
      long_text: "long"
    }

    assert {:ok, bin} = RequiredDecodeWarningOptionalWriter.encode(orig, header: false)

    assert {:error, {:required_field_absent, :medium_text}} =
             RequiredDecodeWarningFixture.decode(bin, header: false)
  end

  test "required fields with defaults use default-only helper arity" do
    orig = %RequiredDecodeWarningOptionalWriter{
      id: nil,
      raw_uuid: nil,
      uuid_text: nil,
      string_default: "default",
      short_text: "short",
      medium_text: nil,
      long_text: "long"
    }

    assert {:ok, payload} = RequiredDecodeWarningOptionalWriter.encode(orig, header: false)
    assert {:ok, decoded} = RequiredDecodeDefaultOnlyFixture.decode(payload, header: false)

    assert decoded.id == 42
    assert decoded.raw_uuid == <<1::128>>
    assert decoded.uuid_text == @uuid_text
    assert decoded.medium_text == "legacy"
  end

  test "mixed required fields use both helper arities" do
    orig = %RequiredDecodeWarningOptionalWriter{
      id: 5,
      raw_uuid: @raw_uuid,
      uuid_text: nil,
      string_default: "default",
      short_text: "short",
      medium_text: "present",
      long_text: "long"
    }

    assert {:ok, payload} = RequiredDecodeWarningOptionalWriter.encode(orig, header: false)
    assert {:ok, decoded} = RequiredDecodeMixedDefaultFixture.decode(payload, header: false)

    assert decoded.id == 5
    assert decoded.uuid_text == @uuid_text
    assert decoded.medium_text == "present"
  end
end
