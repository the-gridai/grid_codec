defmodule GridCodec.RegistryTest do
  use ExUnit.Case, async: true

  alias GridCodec.Registry

  # Define test codecs
  defmodule TestCodecA do
    use GridCodec

    defcodec do
      field(:id, :u64)
      field(:order_id, :uuid)
      field(:price, :u64)
    end
  end

  defmodule TestCodecB do
    use GridCodec

    defcodec do
      field(:id, :u32)
      field(:order_id, :uuid)
      field(:name, :string16)
    end
  end

  defmodule TestCodecC do
    use GridCodec

    defcodec do
      field(:timestamp, :timestamp_us)
      field(:value, :f64)
    end
  end

  describe "list_codecs/1" do
    test "finds loaded GridCodec modules" do
      codecs = Registry.list_codecs()

      # Our test codecs should be in the list
      assert TestCodecA in codecs
      assert TestCodecB in codecs
      assert TestCodecC in codecs
    end

    test "filters by namespace" do
      codecs =
        Registry.list_codecs(namespace: GridCodec.RegistryTest)

      assert TestCodecA in codecs
      assert TestCodecB in codecs
      assert TestCodecC in codecs

      # Should not include codecs from other namespaces
      other_codecs = Registry.list_codecs(namespace: SomeOtherNamespace)
      refute TestCodecA in other_codecs
    end

    test "accepts custom filter function" do
      # Only codecs with :price field
      codecs =
        Registry.list_codecs(filter: fn mod ->
          :price in mod.__fields__()
        end)

      assert TestCodecA in codecs
      refute TestCodecB in codecs
      refute TestCodecC in codecs
    end
  end

  describe "codec_info/1" do
    test "returns codec information" do
      info = Registry.codec_info(TestCodecA)

      assert info.module == TestCodecA
      assert info.fields == [:id, :order_id, :price]
      assert :id in info.fixed_fields
      assert info.block_length > 0
      assert info.version == 1
      assert info.endian == :little
    end

    test "returns nil for non-codec modules" do
      assert Registry.codec_info(String) == nil
      assert Registry.codec_info(Enum) == nil
    end
  end

  describe "find_by_field/2" do
    test "finds codecs with a specific field" do
      # Both TestCodecA and TestCodecB have :order_id
      codecs = Registry.find_by_field(:order_id)

      assert TestCodecA in codecs
      assert TestCodecB in codecs
      refute TestCodecC in codecs
    end

    test "returns empty list for unknown field" do
      codecs = Registry.find_by_field(:nonexistent_field_xyz)
      assert codecs == []
    end
  end

  describe "all_fields/1" do
    test "returns all unique fields" do
      fields = Registry.all_fields(namespace: GridCodec.RegistryTest)

      # Check some expected fields exist
      assert :id in fields
      assert :order_id in fields
      assert :price in fields
      assert :timestamp in fields
      assert :value in fields

      # Should be unique and sorted
      assert fields == Enum.uniq(fields)
      assert fields == Enum.sort(fields)
    end
  end

  describe "summary/1" do
    test "returns summary statistics" do
      summary = Registry.summary(namespace: GridCodec.RegistryTest)

      assert summary.total_codecs == 3
      assert summary.total_fields > 0
      assert summary.total_block_bytes > 0
      assert length(summary.codecs) == 3

      # Check codec summary structure
      codec_a_summary =
        Enum.find(summary.codecs, fn c -> c.module == TestCodecA end)

      assert codec_a_summary.fields == 3
      assert codec_a_summary.block_length > 0
    end
  end

  describe "validate/1" do
    test "returns ok for valid codecs" do
      assert {:ok, info} = Registry.validate(TestCodecA)
      assert info.module == TestCodecA
    end

    test "returns error for non-codec modules" do
      assert {:error, :not_a_gridcodec} = Registry.validate(String)
    end

    test "returns error for non-existent modules" do
      assert {:error, :module_not_found} =
               Registry.validate(NonExistentModule12345)
    end
  end
end
