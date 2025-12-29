defmodule GridCodec.HeaderTest do
  use ExUnit.Case
  use ExUnitProperties

  alias GridCodec.Header

  describe "encode/1" do
    test "encodes header with all fields" do
      binary =
        Header.encode(
          block_length: 64,
          template_id: 1,
          schema_id: 100,
          version: 2
        )

      assert binary == <<64, 0, 1, 0, 100, 0, 2, 0>>
    end

    test "uses defaults for schema_id and version" do
      binary = Header.encode(block_length: 32, template_id: 5)

      assert binary == <<32, 0, 5, 0, 0, 0, 1, 0>>
    end

    test "raises on missing required fields" do
      assert_raise KeyError, fn ->
        Header.encode(template_id: 1)
      end

      assert_raise KeyError, fn ->
        Header.encode(block_length: 32)
      end
    end
  end

  describe "decode/1" do
    test "decodes valid header" do
      binary = <<64, 0, 1, 0, 100, 0, 2, 0, "payload">>

      {:ok, info, rest} = Header.decode(binary)

      assert info == %{
               block_length: 64,
               template_id: 1,
               schema_id: 100,
               version: 2
             }

      assert rest == "payload"
    end

    test "returns error on insufficient data" do
      {:error, reason} = Header.decode(<<1, 2, 3>>)

      assert {:insufficient_data, 3, 8} = reason
    end
  end

  describe "decode!/1" do
    test "returns tuple on success" do
      binary = <<32, 0, 1, 0, 0, 0, 1, 0, "data">>
      {info, rest} = Header.decode!(binary)

      assert info.block_length == 32
      assert rest == "data"
    end

    test "raises on invalid header" do
      assert_raise ArgumentError, ~r/Invalid header/, fn ->
        Header.decode!(<<1, 2, 3>>)
      end
    end
  end

  describe "template_id/1" do
    test "extracts template_id without full decode" do
      binary = <<64, 0, 42, 0, 100, 0, 1, 0>>
      {:ok, id} = Header.template_id(binary)

      assert id == 42
    end

    test "returns error on insufficient data" do
      {:error, :insufficient_data} = Header.template_id(<<1, 2>>)
    end
  end

  describe "validate/2" do
    test "returns :ok for valid header" do
      binary = Header.encode(block_length: 64, template_id: 1)
      assert :ok = Header.validate(binary)
    end

    test "returns error when block_length exceeded" do
      binary = Header.encode(block_length: 10_000, template_id: 1)
      {:error, reason} = Header.validate(binary, max_block_length: 1000)

      assert {:block_length_exceeded, 10_000, 1000} = reason
    end

    test "returns error when version exceeded" do
      binary = Header.encode(block_length: 64, template_id: 1, version: 100)
      {:error, reason} = Header.validate(binary, max_version: 10)

      assert {:version_exceeded, 100, 10} = reason
    end
  end

  describe "size/0" do
    test "returns 8 bytes" do
      assert Header.size() == 8
    end
  end

  # ============================================================================
  # Property-Based Tests
  # ============================================================================

  describe "property: header roundtrip" do
    property "encode/decode roundtrip" do
      check all(
              block_length <- StreamData.integer(0..65_535),
              template_id <- StreamData.integer(0..65_535),
              schema_id <- StreamData.integer(0..65_535),
              version <- StreamData.integer(0..65_535),
              max_runs: 100
            ) do
        binary =
          Header.encode(
            block_length: block_length,
            template_id: template_id,
            schema_id: schema_id,
            version: version
          )

        {:ok, info, ""} = Header.decode(binary)

        assert info.block_length == block_length
        assert info.template_id == template_id
        assert info.schema_id == schema_id
        assert info.version == version
      end
    end

    property "size is constant" do
      check all(
              block_length <- StreamData.integer(0..65_535),
              template_id <- StreamData.integer(0..65_535),
              max_runs: 50
            ) do
        binary = Header.encode(block_length: block_length, template_id: template_id)
        assert byte_size(binary) == Header.size()
      end
    end
  end
end
