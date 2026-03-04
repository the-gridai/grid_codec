defmodule GridCodec.ValidationTest do
  use ExUnit.Case, async: true

  defmodule ValidatedCodec do
    use GridCodec.Struct,
      template_id: 860,
      schema_id: 60,
      version: 1,
      validate: true

    defcodec do
      field :count, :u32
      field :score, :i8
      field :active, :bool
      field :id, :uuid
      field :price, :decimal
      field :created_at, :timestamp_us
    end
  end

  defmodule UnvalidatedCodec do
    use GridCodec.Struct,
      template_id: 861,
      schema_id: 60,
      version: 1,
      validate: false

    defcodec do
      field :count, :u32
    end
  end

  describe "validation enabled" do
    test "valid data encodes normally" do
      struct = %ValidatedCodec{
        count: 100,
        score: -5,
        active: true,
        id: <<1::128>>,
        price: Decimal.new("100.50"),
        created_at: System.system_time(:microsecond)
      }

      binary = ValidatedCodec.encode(struct)
      assert {:ok, _decoded} = ValidatedCodec.decode(binary)
    end

    test "nil values are accepted" do
      struct = %ValidatedCodec{}
      binary = ValidatedCodec.encode(struct)
      assert {:ok, _} = ValidatedCodec.decode(binary)
    end

    test "u32 overflow raises ValidationError" do
      struct = %ValidatedCodec{count: 5_000_000_000}

      error =
        assert_raise GridCodec.ValidationError, fn ->
          ValidatedCodec.encode(struct)
        end

      assert error.code == :out_of_range
      assert error.details.field == :count
      assert error.details.type == :u32
      assert error.details.value == 5_000_000_000
      assert error.details.module == ValidatedCodec
      assert error.message =~ "out of range"
      assert error.message =~ ":count"
    end

    test "u32 negative raises ValidationError" do
      struct = %ValidatedCodec{count: -1}

      error =
        assert_raise GridCodec.ValidationError, fn ->
          ValidatedCodec.encode(struct)
        end

      assert error.code == :out_of_range
      assert error.details.field == :count
    end

    test "i8 overflow raises ValidationError" do
      struct = %ValidatedCodec{score: 200}

      error =
        assert_raise GridCodec.ValidationError, fn ->
          ValidatedCodec.encode(struct)
        end

      assert error.code == :out_of_range
      assert error.details.field == :score
      assert error.details.type == :i8
      assert error.message =~ "-128..127"
    end

    test "bool wrong type raises ValidationError" do
      struct = %ValidatedCodec{active: "yes"}

      error =
        assert_raise GridCodec.ValidationError, fn ->
          ValidatedCodec.encode(struct)
        end

      assert error.code == :type_mismatch
      assert error.details.field == :active
      assert error.details.type == :bool
      assert error.message =~ "true, false, or nil"
    end

    test "uuid wrong format raises ValidationError" do
      struct = %ValidatedCodec{id: "not-a-uuid"}

      error =
        assert_raise GridCodec.ValidationError, fn ->
          ValidatedCodec.encode(struct)
        end

      assert error.code == :invalid_format
      assert error.details.field == :id
      assert error.details.type == :uuid
    end

    test "decimal wrong type raises ValidationError" do
      struct = %ValidatedCodec{price: "100.50"}

      error =
        assert_raise GridCodec.ValidationError, fn ->
          ValidatedCodec.encode(struct)
        end

      assert error.code == :type_mismatch
      assert error.details.field == :price
      assert error.details.type == :decimal
      assert error.message =~ "Decimal"
    end

    test "timestamp wrong type raises ValidationError" do
      struct = %ValidatedCodec{created_at: "2026-01-01"}

      error =
        assert_raise GridCodec.ValidationError, fn ->
          ValidatedCodec.encode(struct)
        end

      assert error.code == :type_mismatch
      assert error.details.field == :created_at
      assert error.details.type == :timestamp_us
      assert error.message =~ "DateTime, integer, or nil"
    end
  end

  describe "validation disabled" do
    test "overflow raises ArgumentError not ValidationError" do
      struct = %UnvalidatedCodec{count: 5_000_000_000}

      error =
        assert_raise ArgumentError, fn ->
          UnvalidatedCodec.encode(struct)
        end

      assert error.message =~ "u32"
      refute is_struct(error, GridCodec.ValidationError)
    end

    test "valid data encodes normally without validation" do
      struct = %UnvalidatedCodec{count: 100}
      binary = UnvalidatedCodec.encode(struct)
      assert {:ok, decoded} = UnvalidatedCodec.decode(binary)
      assert decoded.count == 100
    end
  end
end
