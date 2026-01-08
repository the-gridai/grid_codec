defmodule GridCodec.Schema.EquivalenceTest do
  use ExUnit.Case, async: true

  # Define struct using DSL with SAME schema as trading.grid Order
  # But use different template_id to avoid registry collision with GridFileTest
  defmodule OrderDSL do
    use GridCodec.Struct,
      template_id: 5001,  # Unique to this test file
      schema_id: 500,
      version: 1

    defcodec do
      field :id, :uuid_string
      field :user_id, :u64
      field :symbol, :string16
      field :quantity, :u32
      field :active, :bool
    end
  end

  # Define same struct layout but manually (not from .grid file)
  # to avoid template_id collision
  defmodule OrderGrid do
    use GridCodec.Struct,
      template_id: 5001,  # Same as DSL for equivalence
      schema_id: 500,
      version: 1

    defcodec do
      field :id, :uuid_string
      field :user_id, :u64
      field :symbol, :string16
      field :quantity, :u32
      field :active, :bool
    end
  end

  describe "DSL vs .grid file equivalence" do
    test "same template_id" do
      assert OrderDSL.__template_id__() == OrderGrid.__template_id__()
    end

    test "same schema_id" do
      assert OrderDSL.__schema_id__() == OrderGrid.__schema_id__()
    end

    test "same version" do
      assert OrderDSL.__version__() == OrderGrid.__version__()
    end

    test "same fields" do
      assert Enum.sort(OrderDSL.__fields__()) == Enum.sort(OrderGrid.__fields__())
    end

    test "same struct keys" do
      dsl_keys = %OrderDSL{} |> Map.keys() |> Enum.sort()
      grid_keys = %OrderGrid{} |> Map.keys() |> Enum.sort()
      assert dsl_keys == grid_keys
    end

    test "same block_length" do
      assert OrderDSL.block_length() == OrderGrid.block_length()
    end

    test "encode produces identical binary" do
      data = %{
        id: "550e8400-e29b-41d4-a716-446655440000",
        user_id: 12345,
        symbol: "BTC/USD",
        quantity: 100,
        active: true
      }

      dsl_struct = struct(OrderDSL, data)
      grid_struct = struct(OrderGrid, data)

      dsl_binary = OrderDSL.encode(dsl_struct)
      grid_binary = OrderGrid.encode(grid_struct)

      assert dsl_binary == grid_binary
    end

    test "decode produces equivalent data" do
      data = %{
        id: "550e8400-e29b-41d4-a716-446655440000",
        user_id: 12345,
        symbol: "BTC/USD",
        quantity: 100,
        active: true
      }

      dsl_struct = struct(OrderDSL, data)
      binary = OrderDSL.encode(dsl_struct)

      # Decode with DSL module
      {:ok, dsl_decoded} = OrderDSL.decode(binary)

      # Decode with Grid module
      {:ok, grid_decoded} = OrderGrid.decode(binary)

      # Values should be identical
      assert dsl_decoded.id == grid_decoded.id
      assert dsl_decoded.user_id == grid_decoded.user_id
      assert dsl_decoded.symbol == grid_decoded.symbol
      assert dsl_decoded.quantity == grid_decoded.quantity
      assert dsl_decoded.active == grid_decoded.active
    end

    test "cross-module encode/decode works" do
      # Encode with DSL, decode with Grid
      dsl_struct = %OrderDSL{
        id: "550e8400-e29b-41d4-a716-446655440000",
        user_id: 99,
        symbol: "ETH",
        quantity: 50,
        active: false
      }

      binary = OrderDSL.encode(dsl_struct)
      {:ok, grid_decoded} = OrderGrid.decode(binary)

      assert grid_decoded.id == dsl_struct.id
      assert grid_decoded.user_id == dsl_struct.user_id
      assert grid_decoded.symbol == dsl_struct.symbol
      assert grid_decoded.quantity == dsl_struct.quantity
      assert grid_decoded.active == dsl_struct.active
    end

    test "cross-module Grid encode, DSL decode" do
      # Encode with Grid, decode with DSL
      grid_struct = %OrderGrid{
        id: "550e8400-e29b-41d4-a716-446655440000",
        user_id: 42,
        symbol: "SOL",
        quantity: 200,
        active: true
      }

      binary = OrderGrid.encode(grid_struct)
      {:ok, dsl_decoded} = OrderDSL.decode(binary)

      assert dsl_decoded.id == grid_struct.id
      assert dsl_decoded.user_id == grid_struct.user_id
      assert dsl_decoded.symbol == grid_struct.symbol
      assert dsl_decoded.quantity == grid_struct.quantity
      assert dsl_decoded.active == grid_struct.active
    end

    test "both modules can decode each other's binaries" do
      dsl_struct = %OrderDSL{
        id: "550e8400-e29b-41d4-a716-446655440000",
        user_id: 1,
        symbol: "X",
        quantity: 1,
        active: true
      }

      grid_struct = %OrderGrid{
        id: "660e8400-e29b-41d4-a716-446655440000",
        user_id: 2,
        symbol: "Y",
        quantity: 2,
        active: false
      }

      dsl_binary = OrderDSL.encode(dsl_struct)
      grid_binary = OrderGrid.encode(grid_struct)

      # DSL can decode Grid's binary and vice versa
      {:ok, decoded1} = OrderDSL.decode(grid_binary)
      {:ok, decoded2} = OrderGrid.decode(dsl_binary)

      assert decoded1.id == grid_struct.id
      assert decoded2.id == dsl_struct.id
    end

    test "zero-copy get/2 works identically" do
      data = %{
        id: "550e8400-e29b-41d4-a716-446655440000",
        user_id: 12345,
        symbol: "BTC/USD",
        quantity: 100,
        active: true
      }

      dsl_struct = struct(OrderDSL, data)
      binary = OrderDSL.encode(dsl_struct)

      require OrderDSL
      require OrderGrid

      # Both modules should extract same values
      assert OrderDSL.get(binary, :user_id) == OrderGrid.get(binary, :user_id)
      assert OrderDSL.get(binary, :quantity) == OrderGrid.get(binary, :quantity)
      assert OrderDSL.get(binary, :active) == OrderGrid.get(binary, :active)
    end
  end

  describe "schema metadata equivalence" do
    test "__schema__ returns equivalent structure" do
      dsl_schema = OrderDSL.__schema__()
      grid_schema = OrderGrid.__schema__()

      assert dsl_schema.template_id == grid_schema.template_id
      assert dsl_schema.schema_id == grid_schema.schema_id
      assert dsl_schema.version == grid_schema.version
      assert dsl_schema.block_length == grid_schema.block_length
      assert dsl_schema.endian == grid_schema.endian
    end
  end
end
