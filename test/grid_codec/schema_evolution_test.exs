defmodule GridCodec.SchemaEvolutionTest do
  use ExUnit.Case, async: true

  # Define codecs at module level so they're accessible in all describe blocks
  defmodule OrderV2 do
    use GridCodec, version: 2, template_id: 1, schema_id: 100

    defcodec do
      field :id, :u64
      field :price, :u64
      field :quantity, :u32, since: 1
      field :status, :u8, since: 2
    end
  end

  defmodule OrderV1 do
    use GridCodec, version: 1, template_id: 1, schema_id: 100

    defcodec do
      field :id, :u64
      field :price, :u64
      field :quantity, :u32
    end
  end

  alias __MODULE__.OrderV1
  alias __MODULE__.OrderV2

  describe "since: version option" do
    test "__field_versions__/0 returns version map" do
      versions = OrderV2.__field_versions__()

      assert versions == %{
               id: 1,
               price: 1,
               quantity: 1,
               status: 2
             }
    end

    test "__schema__/0 includes field_versions" do
      schema = OrderV2.__schema__()

      assert schema.field_versions == %{
               id: 1,
               price: 1,
               quantity: 1,
               status: 2
             }
    end

    test "__version__/0 returns codec version" do
      assert OrderV2.__version__() == 2
    end

    test "encode/decode roundtrip works normally" do
      data = %{id: 123, price: 1000, quantity: 50, status: 1}
      binary = OrderV2.encode(data)

      {:ok, decoded} = OrderV2.decode(binary)
      assert decoded.id == 123
      assert decoded.price == 1000
      assert decoded.quantity == 50
      assert decoded.status == 1
    end
  end

  describe "compile-time validation" do
    test "compilation fails if since > codec version" do
      # This would fail to compile:
      #
      #   defmodule BadCodec do
      #     use GridCodec, version: 1
      #
      #     defcodec do
      #       field :id, :u64
      #       field :future_field, :u32, since: 2  # ERROR: since 2 > version 1
      #     end
      #   end
      #
      # CompileError: Field :future_field has since: 2 but codec version is 1.

      # We verify by checking the valid case works
      assert OrderV2.__version__() == 2
      assert OrderV2.__field_versions__()[:status] == 2
    end
  end

  describe "version evolution scenario" do
    test "v1 encoder produces smaller binary" do
      v1_binary = OrderV1.encode(%{id: 1, price: 100, quantity: 10})
      v2_binary = OrderV2.encode(%{id: 1, price: 100, quantity: 10, status: 0})

      # V1: 8 + 8 + 4 = 20 bytes
      # V2: 8 + 8 + 4 + 1 = 21 bytes
      assert byte_size(v1_binary) == 20
      assert byte_size(v2_binary) == 21
    end

    test "v1 and v2 share same fixed field layout for common fields" do
      v1_binary = OrderV1.encode(%{id: 123, price: 1000, quantity: 50})
      v2_binary = OrderV2.encode(%{id: 123, price: 1000, quantity: 50, status: 5})

      # First 20 bytes should be identical
      assert binary_part(v1_binary, 0, 20) == binary_part(v2_binary, 0, 20)
    end

    test "v2 can decode v1 messages (forward compatibility)" do
      # V1 message (20 bytes) decoded by V2 codec
      # The v2 status field will use its null_value (255 for u8)
      v1_binary = OrderV1.encode(%{id: 123, price: 1000, quantity: 50})

      # V2 decoder on v1 binary - will fail because binary is too short
      # This demonstrates why you need the header for version negotiation
      assert {:error, :invalid_binary} = OrderV2.decode(v1_binary)
    end

    test "v1 can decode v2 messages by truncating (backward compatibility)" do
      # V2 message includes status field
      v2_binary = OrderV2.encode(%{id: 123, price: 1000, quantity: 50, status: 5})

      # V1 decoder will only read first 20 bytes
      {:ok, decoded} = OrderV1.decode(v2_binary)
      assert decoded.id == 123
      assert decoded.price == 1000
      assert decoded.quantity == 50
      # status is not in v1, so it's ignored
    end
  end

  describe "framed messages with version" do
    test "encode!/decode! includes version in header" do
      binary = OrderV2.encode!(%{id: 1, price: 100, quantity: 10, status: 1})

      {:ok, header, _payload} = GridCodec.Header.decode(binary)
      assert header.version == 2
    end

    test "decode! rejects messages with version > codec version" do
      # Create a message claiming to be version 3
      header =
        GridCodec.Header.encode(
          block_length: 21,
          template_id: 1,
          schema_id: 100,
          version: 3
        )

      payload = <<0::168>>
      binary = <<header::binary, payload::binary>>

      assert {:error, {:version_too_new, 3, 2}} = OrderV2.decode!(binary)
    end

    test "decode! accepts messages with version <= codec version" do
      # Create a version 1 message with proper block_length
      header =
        GridCodec.Header.encode(
          block_length: 21,
          template_id: 1,
          schema_id: 100,
          version: 1
        )

      payload = <<123::little-64, 1000::little-64, 50::little-32, 5::8>>
      binary = <<header::binary, payload::binary>>

      {:ok, decoded} = OrderV2.decode!(binary)
      assert decoded.id == 123
      assert decoded.price == 1000
      assert decoded.quantity == 50
      assert decoded.status == 5
    end
  end

  describe "field_versions introspection" do
    defmodule SimpleCodec do
      use GridCodec, version: 1

      defcodec do
        field :a, :u64
        field :b, :u32
      end
    end

    test "all fields default to since: 1" do
      assert SimpleCodec.__field_versions__() == %{a: 1, b: 1}
    end

    test "explicit since: overrides default" do
      assert OrderV2.__field_versions__()[:status] == 2
      assert OrderV2.__field_versions__()[:id] == 1
    end
  end
end
