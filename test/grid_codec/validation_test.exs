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

      {:ok, binary} = ValidatedCodec.encode(struct)
      assert {:ok, _decoded} = ValidatedCodec.decode(binary)
    end

    test "nil values are accepted" do
      struct = %ValidatedCodec{}
      {:ok, binary} = ValidatedCodec.encode(struct)
      assert {:ok, _} = ValidatedCodec.decode(binary)
    end

    test "u32 overflow returns ValidationError" do
      struct = %ValidatedCodec{count: 5_000_000_000}

      assert {:error, error} = ValidatedCodec.encode(struct)

      assert error.code == :out_of_range
      assert error.details.field == :count
      assert error.details.type == :u32
      assert error.details.value == 5_000_000_000
      assert error.details.module == ValidatedCodec
      assert Exception.message(error) =~ "out of range"
      assert Exception.message(error) =~ ":count"
    end

    test "u32 negative returns ValidationError" do
      struct = %ValidatedCodec{count: -1}

      assert {:error, error} = ValidatedCodec.encode(struct)

      assert error.code == :out_of_range
      assert error.details.field == :count
    end

    test "i8 overflow returns ValidationError" do
      struct = %ValidatedCodec{score: 200}

      assert {:error, error} = ValidatedCodec.encode(struct)

      assert error.code == :out_of_range
      assert error.details.field == :score
      assert error.details.type == :i8
      assert Exception.message(error) =~ "-128..127"
    end

    test "bool wrong type returns ValidationError" do
      struct = %ValidatedCodec{active: "yes"}

      assert {:error, error} = ValidatedCodec.encode(struct)

      assert error.code == :type_mismatch
      assert error.details.field == :active
      assert error.details.type == :bool
      assert Exception.message(error) =~ "true, false, or nil"
    end

    test "uuid wrong format returns ValidationError" do
      struct = %ValidatedCodec{id: "not-a-uuid"}

      assert {:error, error} = ValidatedCodec.encode(struct)

      assert error.code == :invalid_format
      assert error.details.field == :id
      assert error.details.type == :uuid
    end

    test "decimal wrong type returns ValidationError" do
      struct = %ValidatedCodec{price: "100.50"}

      assert {:error, error} = ValidatedCodec.encode(struct)

      assert error.code == :type_mismatch
      assert error.details.field == :price
      assert error.details.type == :decimal
      assert Exception.message(error) =~ "Decimal"
    end

    test "timestamp wrong type returns ValidationError" do
      struct = %ValidatedCodec{created_at: "2026-01-01"}

      assert {:error, error} = ValidatedCodec.encode(struct)

      assert error.code == :type_mismatch
      assert error.details.field == :created_at
      assert error.details.type == :timestamp_us
      assert Exception.message(error) =~ "DateTime, integer, or nil"
    end
  end

  describe "new/1 constructor" do
    test "returns {:ok, struct} for valid data" do
      assert {:ok, %ValidatedCodec{count: 100, active: true}} =
               ValidatedCodec.new(count: 100, active: true)
    end

    test "returns {:ok, struct} with defaults for empty attrs" do
      assert {:ok, %ValidatedCodec{}} = ValidatedCodec.new()
    end

    test "returns {:error, %ValidationError{}} for invalid data" do
      assert {:error, %GridCodec.ValidationError{code: :cast_error} = error} =
               ValidatedCodec.new(count: 5_000_000_000)

      assert error.details.field == :count
      assert error.details.value == 5_000_000_000
    end

    test "returns {:error, ...} for uncoercible value" do
      assert {:error, %GridCodec.ValidationError{code: :cast_error} = e} =
               ValidatedCodec.new(active: "yes")

      assert e.details.field == :active
    end

    test "accepts map input" do
      assert {:ok, %ValidatedCodec{count: 42}} = ValidatedCodec.new(%{count: 42})
    end
  end

  describe "encode/1 error handling" do
    test "returns {:ok, binary} for valid data" do
      {:ok, struct} = ValidatedCodec.new(count: 42)
      assert {:ok, binary} = ValidatedCodec.encode(struct)
      assert is_binary(binary)
    end

    test "returns {:error, %ValidationError{}} for invalid data" do
      struct = %ValidatedCodec{count: 5_000_000_000}
      assert {:error, %GridCodec.ValidationError{}} = ValidatedCodec.encode(struct)
    end
  end

  describe "new/1 without validation" do
    test "still returns {:ok, struct} (no validation errors)" do
      assert {:ok, %UnvalidatedCodec{count: 100}} = UnvalidatedCodec.new(count: 100)
    end

    test "coercion rejects out-of-range values even without validation" do
      assert {:error, %GridCodec.ValidationError{code: :cast_error} = error} =
               UnvalidatedCodec.new(count: 5_000_000_000)

      assert error.details.field == :count
      assert error.details.description =~ "out of range"
    end
  end

  describe "update/2" do
    test "updates a field with coercion" do
      {:ok, struct} = ValidatedCodec.new(count: 42, score: -5)
      {:ok, updated} = ValidatedCodec.update(struct, count: 99)
      assert updated.count == 99
      assert updated.score == -5
    end

    test "updates from string keys and values" do
      {:ok, struct} = ValidatedCodec.new(count: 42)
      {:ok, updated} = ValidatedCodec.update(struct, %{"count" => "100"})
      assert updated.count == 100
    end

    test "validates updated fields" do
      {:ok, struct} = ValidatedCodec.new(count: 42)

      {:error, %GridCodec.ValidationError{code: :cast_error}} =
        ValidatedCodec.update(struct, count: 5_000_000_000)
    end

    test "coercion error on update" do
      {:ok, struct} = ValidatedCodec.new(count: 42)

      {:error, %GridCodec.ValidationError{code: :cast_error}} =
        ValidatedCodec.update(struct, %{"count" => "bad"})
    end

    test "preserves unchanged fields" do
      {:ok, struct} = ValidatedCodec.new(count: 42, score: -5, active: true)
      {:ok, updated} = ValidatedCodec.update(struct, score: 10)
      assert updated.count == 42
      assert updated.score == 10
      assert updated.active == true
    end
  end

  describe "validation disabled" do
    test "overflow returns error" do
      struct = %UnvalidatedCodec{count: 5_000_000_000}

      assert {:error, error} = UnvalidatedCodec.encode(struct)
      assert Exception.message(error) =~ "u32"
    end

    test "valid data encodes normally without validation" do
      struct = %UnvalidatedCodec{count: 100}
      {:ok, binary} = UnvalidatedCodec.encode(struct)
      assert {:ok, decoded} = UnvalidatedCodec.decode(binary)
      assert decoded.count == 100
    end
  end

  # ======================================================================
  # Coercion hardening tests
  # ======================================================================

  describe "integer coercion range checks" do
    test "u32 rejects negative values via coercion" do
      assert {:error, %GridCodec.ValidationError{} = e} = UnvalidatedCodec.new(count: -1)
      assert e.details.field == :count
      assert e.details.description =~ "out of range"
    end

    test "u32 rejects overflow" do
      assert {:error, %GridCodec.ValidationError{} = e} =
               UnvalidatedCodec.new(count: 4_294_967_296)

      assert e.details.field == :count
    end

    test "u32 accepts boundary values" do
      assert {:ok, %UnvalidatedCodec{count: 0}} = UnvalidatedCodec.new(count: 0)

      assert {:ok, %UnvalidatedCodec{count: 4_294_967_294}} =
               UnvalidatedCodec.new(count: 4_294_967_294)
    end

    test "i8 rejects out-of-range values" do
      assert {:error, %GridCodec.ValidationError{} = e} =
               ValidatedCodec.new(count: 42, score: 200, active: true)

      assert e.details.field == :score
      assert e.details.description =~ "out of range"
    end

    test "i8 accepts boundary values" do
      assert {:ok, _} = ValidatedCodec.new(count: 42, score: -127, active: true)
      assert {:ok, _} = ValidatedCodec.new(count: 42, score: 127, active: true)
    end

    test "string-parsed integers also range-checked" do
      assert {:error, %GridCodec.ValidationError{} = e} =
               UnvalidatedCodec.new(count: "5000000000")

      assert e.details.field == :count
      assert e.details.description =~ "out of range"
    end

    test "string-parsed integers within range accepted" do
      assert {:ok, %UnvalidatedCodec{count: 42}} = UnvalidatedCodec.new(count: "42")
    end
  end

  describe "enum coercion hardening" do
    defmodule EnumTestCodec do
      use GridCodec.Struct,
        template_id: 866,
        schema_id: 60,
        version: 1,
        validate: false

      defcodec do
        field :side, GridCodec.TestSupport.Side
      end
    end

    test "accepts known atom values" do
      assert {:ok, %EnumTestCodec{side: :buy}} = EnumTestCodec.new(side: :buy)
      assert {:ok, %EnumTestCodec{side: :sell}} = EnumTestCodec.new(side: :sell)
    end

    test "accepts known string values" do
      assert {:ok, %EnumTestCodec{side: :buy}} = EnumTestCodec.new(side: "buy")
      assert {:ok, %EnumTestCodec{side: :sell}} = EnumTestCodec.new(side: "sell")
    end

    test "accepts known integer values" do
      assert {:ok, %EnumTestCodec{side: :buy}} = EnumTestCodec.new(side: 0)
      assert {:ok, %EnumTestCodec{side: :sell}} = EnumTestCodec.new(side: 1)
    end

    test "rejects unknown integer values" do
      assert {:error, %GridCodec.ValidationError{code: :cast_error} = e} =
               EnumTestCodec.new(side: 99)

      assert e.details.field == :side
      assert e.details.description =~ "invalid enum value"
    end

    test "rejects unknown atom values" do
      assert {:error, %GridCodec.ValidationError{code: :cast_error} = e} =
               EnumTestCodec.new(side: :nonexistent)

      assert e.details.field == :side
      assert e.details.description =~ "invalid enum value"
    end

    test "rejects unknown string values" do
      assert {:error, %GridCodec.ValidationError{code: :cast_error} = e} =
               EnumTestCodec.new(side: "unknown")

      assert e.details.field == :side
      assert e.details.description =~ "invalid enum value"
    end

    test "accepts nil" do
      assert {:ok, %EnumTestCodec{side: nil}} = EnumTestCodec.new(side: nil)
    end
  end

  describe "UUID coercion safety" do
    test "malformed 36-char string returns error instead of raising" do
      bad_uuid = "GGGGGGGG-GGGG-GGGG-GGGG-GGGGGGGGGGGG"

      assert {:error, %GridCodec.ValidationError{code: :cast_error} = e} =
               ValidatedCodec.new(count: 1, id: bad_uuid)

      assert e.details.field == :id
      assert e.details.description =~ "invalid UUID"
    end

    test "malformed 32-char string returns error instead of raising" do
      bad_uuid = "GGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG"

      assert {:error, %GridCodec.ValidationError{code: :cast_error} = e} =
               ValidatedCodec.new(count: 1, id: bad_uuid)

      assert e.details.field == :id
      assert e.details.description =~ "invalid UUID"
    end

    test "valid UUID strings still work" do
      good_uuid = "550e8400-e29b-41d4-a716-446655440000"
      assert {:ok, codec} = ValidatedCodec.new(count: 1, id: good_uuid)
      assert is_binary(codec.id) and byte_size(codec.id) == 16
    end
  end

  describe "string coercion" do
    defmodule StringTestCodec do
      use GridCodec.Struct,
        template_id: 867,
        schema_id: 60,
        version: 1,
        validate: false

      defcodec do
        field :name, :string16
      end
    end

    test "coerces atoms to strings" do
      assert {:ok, %StringTestCodec{name: "hello"}} = StringTestCodec.new(name: :hello)
    end

    test "coerces numbers to strings" do
      assert {:ok, %StringTestCodec{name: "42"}} = StringTestCodec.new(name: 42)
      assert {:ok, %StringTestCodec{name: "3.14"}} = StringTestCodec.new(name: 3.14)
    end

    test "passes through binaries" do
      assert {:ok, %StringTestCodec{name: "hello"}} = StringTestCodec.new(name: "hello")
    end

    test "rejects non-stringable values" do
      assert {:error, %GridCodec.ValidationError{code: :cast_error} = e} =
               StringTestCodec.new(name: %{key: "value"})

      assert e.details.field == :name
      assert e.details.description =~ "expected string"
    end

    test "nil passes through" do
      assert {:ok, %StringTestCodec{name: nil}} = StringTestCodec.new(name: nil)
    end
  end

  describe "encode error field name preservation" do
    test "encode error includes field name instead of :unknown" do
      struct = %UnvalidatedCodec{count: 5_000_000_000}
      assert {:error, %GridCodec.ValidationError{} = e} = UnvalidatedCodec.encode(struct)
      assert e.details.field == :count
    end
  end
end
