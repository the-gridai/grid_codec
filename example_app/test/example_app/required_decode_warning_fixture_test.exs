defmodule ExampleApp.RequiredDecodeWarningFixtureTest do
  use ExUnit.Case, async: true

  alias ExampleApp.Events.RequiredDecodeWarningFixture
  alias ExampleApp.Events.RequiredDecodeWarningOptionalWriter

  @raw_uuid <<0x55, 0x0E, 0x84, 0x00, 0xE2, 0x9B, 0x41, 0xD4, 0xA7, 0x16, 0x44, 0x66, 0x55, 0x44,
              0x00, 0x00>>
  @uuid_text "550e8400-e29b-41d4-a716-446655440000"

  test "required string and uuid_string fields round-trip in the example app" do
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

    assert decoded.uuid_text == @uuid_text
    assert decoded.string_default == "default"
    assert decoded.short_text == "short"
    assert decoded.medium_text == "medium"
    assert decoded.long_text == "long"
  end

  test "required nil sentinels still fail decode in the example app" do
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
end
