defmodule GridCodec.CastAndHashTest do
  use ExUnit.Case, async: true

  defmodule TestCodec do
    use GridCodec.Struct,
      template_id: 870,
      schema_id: 60,
      version: 1

    defcodec do
      field :count, :u32
      field :score, :i64
      field :active, :bool
      field :price, :decimal
      field :id, :uuid
      field :created_at, :timestamp_us
      field :ratio, :f64
      field :name, :string
    end
  end

  # ============================================================================
  # Cast
  # ============================================================================

  describe "cast/1 with atom keys" do
    test "passes through correctly typed values" do
      assert {:ok, %TestCodec{count: 42, active: true}} =
               TestCodec.cast(count: 42, active: true)
    end

    test "coerces string integers" do
      assert {:ok, %TestCodec{count: 42, score: -100}} =
               TestCodec.cast(count: "42", score: "-100")
    end

    test "coerces string booleans" do
      assert {:ok, %TestCodec{active: true}} = TestCodec.cast(active: "true")
      assert {:ok, %TestCodec{active: false}} = TestCodec.cast(active: "false")
    end

    test "coerces integer booleans" do
      assert {:ok, %TestCodec{active: true}} = TestCodec.cast(active: 1)
      assert {:ok, %TestCodec{active: false}} = TestCodec.cast(active: 0)
    end

    test "coerces string decimals" do
      assert {:ok, %TestCodec{price: %Decimal{}}} = TestCodec.cast(price: "100.50")
    end

    test "coerces ISO 8601 timestamps" do
      assert {:ok, %TestCodec{created_at: %DateTime{}}} =
               TestCodec.cast(created_at: "2026-01-01T00:00:00Z")
    end

    test "coerces string floats" do
      assert {:ok, %TestCodec{ratio: 3.14}} = TestCodec.cast(ratio: "3.14")
    end

    test "coerces UUID strings to binary" do
      uuid_str = "550e8400-e29b-41d4-a716-446655440000"
      assert {:ok, %TestCodec{id: <<_::128>>}} = TestCodec.cast(id: uuid_str)
    end

    test "nil values pass through" do
      assert {:ok, %TestCodec{count: nil}} = TestCodec.cast(%{})
    end
  end

  describe "cast/1 with string keys" do
    test "accepts string keys from JSON-like input" do
      assert {:ok, %TestCodec{count: 42, active: true}} =
               TestCodec.cast(%{"count" => "42", "active" => "true"})
    end

    test "mixed string and atom keys" do
      assert {:ok, %TestCodec{count: 42, active: true}} =
               TestCodec.cast(%{"count" => "42", active: true})
    end
  end

  describe "cast/1 error handling" do
    test "returns error for unparseable integer" do
      assert {:error, :count, reason} = TestCodec.cast(count: "not_a_number")
      assert reason =~ "cannot parse integer"
    end

    test "returns error for unparseable boolean" do
      assert {:error, :active, reason} = TestCodec.cast(active: "maybe")
      assert reason =~ "expected boolean"
    end

    test "returns error for unparseable decimal" do
      assert {:error, :price, reason} = TestCodec.cast(price: "abc")
      assert reason =~ "cannot parse decimal"
    end

    test "returns error for bad timestamp" do
      assert {:error, :created_at, reason} = TestCodec.cast(created_at: "not-a-date")
      assert reason =~ "cannot parse datetime"
    end

    test "returns error for bad UUID" do
      assert {:error, :id, reason} = TestCodec.cast(id: "too-short")
      assert reason =~ "UUID"
    end

    test "stops at first error" do
      assert {:error, field, _reason} =
               TestCodec.cast(count: "bad", active: "also_bad")

      assert field in [:count, :active]
    end
  end

  # ============================================================================
  # Content Hash
  # ============================================================================

  describe "content_hash/1" do
    test "returns 32-byte SHA-256" do
      struct = %TestCodec{count: 42, active: true, ratio: 1.0}
      hash = TestCodec.content_hash(struct)
      assert byte_size(hash) == 32
    end

    test "same data produces same hash" do
      struct = %TestCodec{count: 42, active: true, price: Decimal.new("100"), ratio: 0.0}
      assert TestCodec.content_hash(struct) == TestCodec.content_hash(struct)
    end

    test "different data produces different hash" do
      a = %TestCodec{count: 42, ratio: 0.0}
      b = %TestCodec{count: 43, ratio: 0.0}
      assert TestCodec.content_hash(a) != TestCodec.content_hash(b)
    end

    test "hash is deterministic across encode cycles" do
      struct = %TestCodec{count: 42, score: -5, active: true, ratio: 3.14}
      hash1 = TestCodec.content_hash(struct)

      binary = TestCodec.encode(struct)
      {:ok, decoded} = TestCodec.decode(binary)
      hash2 = TestCodec.content_hash(decoded)

      assert hash1 == hash2
    end

    test "hash is independent of struct key ordering" do
      a = %TestCodec{count: 1, score: 2, ratio: 0.0}
      b = struct!(TestCodec, %{score: 2, count: 1, ratio: 0.0})
      assert TestCodec.content_hash(a) == TestCodec.content_hash(b)
    end
  end

  # ============================================================================
  # Projection: decode_only
  # ============================================================================

  describe "decode_only/2" do
    test "decodes only requested fields" do
      struct = %TestCodec{count: 42, score: -5, active: true, ratio: 3.14}
      binary = TestCodec.encode(struct)

      assert {:ok, view} = TestCodec.decode_only(binary, [:count, :active])
      assert view.count == 42
      assert view.active == true
      assert map_size(view) == 2
    end

    test "single field projection" do
      struct = %TestCodec{count: 99, ratio: 0.0}
      binary = TestCodec.encode(struct)

      assert {:ok, %{count: 99}} = TestCodec.decode_only(binary, [:count])
    end

    test "nil field in projection" do
      struct = %TestCodec{count: nil, ratio: 0.0}
      binary = TestCodec.encode(struct)

      assert {:ok, %{count: nil}} = TestCodec.decode_only(binary, [:count])
    end

    test "unknown field returns nil" do
      struct = %TestCodec{count: 42, ratio: 0.0}
      binary = TestCodec.encode(struct)

      assert {:ok, view} = TestCodec.decode_only(binary, [:count, :nonexistent])
      assert view.count == 42
      assert view.nonexistent == nil
    end

    test "empty field list returns empty map" do
      struct = %TestCodec{ratio: 0.0}
      binary = TestCodec.encode(struct)

      assert {:ok, view} = TestCodec.decode_only(binary, [])
      assert view == %{}
    end

    test "decimal field projection" do
      struct = %TestCodec{price: Decimal.new("100.50"), ratio: 0.0}
      binary = TestCodec.encode(struct)

      assert {:ok, %{price: price}} = TestCodec.decode_only(binary, [:price])
      assert Decimal.equal?(price, Decimal.new("100.50"))
    end

    test "bool + integer projection skips all other fields" do
      struct = %TestCodec{
        count: 42,
        score: -100,
        active: true,
        price: Decimal.new("999"),
        id: <<1::128>>,
        created_at: 1_700_000_000_000_000,
        ratio: 3.14,
        name: "test"
      }

      binary = TestCodec.encode(struct)

      assert {:ok, view} = TestCodec.decode_only(binary, [:active, :score])
      assert view == %{active: true, score: -100}
    end
  end
end
