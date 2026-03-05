defmodule GridCodec.Types.UUIDTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias GridCodec.Types.UUID

  describe "generate_v4/0" do
    test "returns 16 bytes with version 4 and variant 1" do
      uuid = UUID.generate_v4()
      assert byte_size(uuid) == 16
      <<_::48, version::4, _::12, variant::2, _::62>> = uuid
      assert version == 4
      assert variant == 2
    end

    test "produces unique values" do
      uuids = for _ <- 1..100, do: UUID.generate_v4()
      assert length(Enum.uniq(uuids)) == 100
    end
  end

  describe "generate_v5/2" do
    test "returns 16 bytes with version 5 and variant 1" do
      uuid = UUID.generate_v5(:dns, "example.com")
      assert byte_size(uuid) == 16
      <<_::48, version::4, _::12, variant::2, _::62>> = uuid
      assert version == 5
      assert variant == 2
    end

    test "is deterministic — same inputs produce same output" do
      a = UUID.generate_v5(:dns, "example.com")
      b = UUID.generate_v5(:dns, "example.com")
      assert a == b
    end

    test "different names produce different UUIDs" do
      a = UUID.generate_v5(:dns, "example.com")
      b = UUID.generate_v5(:dns, "example.org")
      assert a != b
    end

    test "different namespaces produce different UUIDs" do
      a = UUID.generate_v5(:dns, "example.com")
      b = UUID.generate_v5(:url, "example.com")
      assert a != b
    end

    test "accepts atom namespace shortcuts" do
      for ns <- [:dns, :url, :oid, :x500] do
        uuid = UUID.generate_v5(ns, "test")
        assert byte_size(uuid) == 16
      end
    end

    test "accepts raw 16-byte namespace" do
      custom_ns = :crypto.strong_rand_bytes(16)
      uuid = UUID.generate_v5(custom_ns, "test")
      assert byte_size(uuid) == 16
      <<_::48, version::4, _::12, variant::2, _::62>> = uuid
      assert version == 5
      assert variant == 2
    end

    test "matches RFC 4122 test vector for DNS + example.com" do
      # RFC 4122 / widely-agreed test vector:
      # v5(DNS, "www.example.com") = 2ed6657d-e927-568b-95e1-2665a8aea6a2
      uuid = UUID.generate_v5(:dns, "www.example.com")
      expected = <<0x2ED6657D::32, 0xE927::16, 0x568B::16, 0x95::8, 0xE1::8, 0x2665A8AEA6A2::48>>
      assert uuid == expected
    end

    property "always produces version 5 variant 1 for any name" do
      check all(name <- StreamData.binary(min_length: 0, max_length: 200)) do
        uuid = UUID.generate_v5(:dns, name)
        <<_::48, version::4, _::12, variant::2, _::62>> = uuid
        assert version == 5
        assert variant == 2
      end
    end
  end

  describe "generate_v7/0" do
    test "returns 16 bytes with version 7 and variant 1" do
      uuid = UUID.generate_v7()
      assert byte_size(uuid) == 16
      <<_::48, version::4, _::12, variant::2, _::62>> = uuid
      assert version == 7
      assert variant == 2
    end

    test "encodes current time in first 48 bits" do
      before_ms = System.system_time(:millisecond)
      uuid = UUID.generate_v7()
      after_ms = System.system_time(:millisecond)

      ts = UUID.v7_timestamp(uuid)
      assert ts >= before_ms
      assert ts <= after_ms
    end

    test "is time-sortable" do
      a = UUID.generate_v7()
      Process.sleep(2)
      b = UUID.generate_v7()
      assert a < b
    end
  end

  describe "v7_timestamp/1" do
    test "extracts timestamp from v7 UUID" do
      uuid = UUID.generate_v7()
      assert is_integer(UUID.v7_timestamp(uuid))
    end

    test "returns nil for non-v7 UUID" do
      assert UUID.v7_timestamp(UUID.generate_v4()) == nil
      assert UUID.v7_timestamp(UUID.generate_v5(:dns, "test")) == nil
    end
  end

  describe "namespace accessors" do
    test "ns_dns returns 16 bytes" do
      assert byte_size(UUID.ns_dns()) == 16
    end

    test "ns_url returns 16 bytes" do
      assert byte_size(UUID.ns_url()) == 16
    end

    test "ns_oid returns 16 bytes" do
      assert byte_size(UUID.ns_oid()) == 16
    end

    test "ns_x500 returns 16 bytes" do
      assert byte_size(UUID.ns_x500()) == 16
    end

    test "all standard namespaces are distinct" do
      namespaces = [UUID.ns_dns(), UUID.ns_url(), UUID.ns_oid(), UUID.ns_x500()]
      assert length(Enum.uniq(namespaces)) == 4
    end
  end
end
