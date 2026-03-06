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

  describe "new/1 with coercion" do
    test "passes through correctly typed values" do
      assert {:ok, %TestCodec{count: 42, active: true}} =
               TestCodec.new(count: 42, active: true)
    end

    test "coerces string integers" do
      assert {:ok, %TestCodec{count: 42, score: -100}} =
               TestCodec.new(count: "42", score: "-100")
    end

    test "coerces string booleans" do
      assert {:ok, %TestCodec{active: true}} = TestCodec.new(active: "true")
      assert {:ok, %TestCodec{active: false}} = TestCodec.new(active: "false")
    end

    test "coerces integer booleans" do
      assert {:ok, %TestCodec{active: true}} = TestCodec.new(active: 1)
      assert {:ok, %TestCodec{active: false}} = TestCodec.new(active: 0)
    end

    test "coerces string decimals" do
      assert {:ok, %TestCodec{price: %Decimal{}}} = TestCodec.new(price: "100.50")
    end

    test "coerces ISO 8601 timestamps to integer microseconds" do
      assert {:ok, %TestCodec{created_at: us}} =
               TestCodec.new(created_at: "2026-01-01T00:00:00Z")

      assert is_integer(us)
      assert us == DateTime.to_unix(~U[2026-01-01 00:00:00Z], :microsecond)
    end

    test "coerces string floats" do
      assert {:ok, %TestCodec{ratio: 3.14}} = TestCodec.new(ratio: "3.14")
    end

    test "coerces UUID strings to binary" do
      uuid_str = "550e8400-e29b-41d4-a716-446655440000"
      assert {:ok, %TestCodec{id: <<_::128>>}} = TestCodec.new(id: uuid_str)
    end

    test "nil values pass through" do
      assert {:ok, %TestCodec{count: nil}} = TestCodec.new(%{})
    end

    test "accepts string keys from JSON-like input" do
      assert {:ok, %TestCodec{count: 42, active: true}} =
               TestCodec.new(%{"count" => "42", "active" => "true"})
    end

    test "mixed string and atom keys" do
      assert {:ok, %TestCodec{count: 42, active: true}} =
               TestCodec.new(%{"count" => "42", active: true})
    end
  end

  describe "new/1 coercion errors" do
    test "returns ValidationError for unparseable integer" do
      assert {:error, %GridCodec.ValidationError{code: :cast_error} = e} =
               TestCodec.new(count: "not_a_number")

      assert e.details.field == :count
      assert Exception.message(e) =~ "cannot cast"
    end

    test "returns ValidationError for unparseable boolean" do
      assert {:error, %GridCodec.ValidationError{code: :cast_error} = e} =
               TestCodec.new(active: "maybe")

      assert e.details.field == :active
    end

    test "returns ValidationError for unparseable decimal" do
      assert {:error, %GridCodec.ValidationError{code: :cast_error}} =
               TestCodec.new(price: "abc")
    end

    test "returns ValidationError for bad timestamp" do
      assert {:error, %GridCodec.ValidationError{code: :cast_error} = e} =
               TestCodec.new(created_at: "not-a-date")

      assert e.details.field == :created_at
    end

    test "returns ValidationError for bad UUID" do
      assert {:error, %GridCodec.ValidationError{code: :cast_error} = e} =
               TestCodec.new(id: "too-short")

      assert e.details.field == :id
    end

    test "stops at first error" do
      assert {:error, %GridCodec.ValidationError{code: :cast_error}} =
               TestCodec.new(count: "bad", active: "also_bad")
    end
  end

  # ============================================================================
  # new_binary/1
  # ============================================================================

  describe "new_binary/1" do
    test "produces valid binary from typed map" do
      {:ok, binary} = TestCodec.new_binary(count: 42, score: -5, active: true, ratio: 1.0)
      assert is_binary(binary)
      assert {:ok, decoded} = TestCodec.decode(binary)
      assert decoded.count == 42
      assert decoded.score == -5
      assert decoded.active == true
    end

    test "produces valid binary from string map" do
      {:ok, binary} =
        TestCodec.new_binary(%{"count" => "42", "active" => "true", "ratio" => "1.0"})

      assert {:ok, decoded} = TestCodec.decode(binary)
      assert decoded.count == 42
      assert decoded.active == true
    end

    test "produces valid binary from existing struct" do
      {:ok, struct} = TestCodec.new(count: 42, ratio: 1.0)
      {:ok, binary} = TestCodec.new_binary(struct)
      {:ok, encoded} = TestCodec.encode(struct)
      assert binary == encoded
    end

    test "produces valid binary from keyword list" do
      {:ok, binary} = TestCodec.new_binary(count: 99, ratio: 0.0)
      assert {:ok, decoded} = TestCodec.decode(binary)
      assert decoded.count == 99
    end

    test "returns error for cast failure" do
      assert {:error, %GridCodec.ValidationError{code: :cast_error}} =
               TestCodec.new_binary(count: "bad")
    end

    test "handles minimal input with defaults" do
      {:ok, binary} = TestCodec.new_binary(%{ratio: 0.0})
      assert is_binary(binary)
      assert {:ok, decoded} = TestCodec.decode(binary)
      assert decoded.ratio == 0.0
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

      {:ok, binary} = TestCodec.encode(struct)
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
      {:ok, binary} = TestCodec.encode(struct)

      assert {:ok, view} = TestCodec.decode_only(binary, [:count, :active])
      assert view.count == 42
      assert view.active == true
      assert map_size(view) == 2
    end

    test "single field projection" do
      struct = %TestCodec{count: 99, ratio: 0.0}
      {:ok, binary} = TestCodec.encode(struct)

      assert {:ok, %{count: 99}} = TestCodec.decode_only(binary, [:count])
    end

    test "nil field in projection" do
      struct = %TestCodec{count: nil, ratio: 0.0}
      {:ok, binary} = TestCodec.encode(struct)

      assert {:ok, %{count: nil}} = TestCodec.decode_only(binary, [:count])
    end

    test "unknown field returns nil" do
      struct = %TestCodec{count: 42, ratio: 0.0}
      {:ok, binary} = TestCodec.encode(struct)

      assert {:ok, view} = TestCodec.decode_only(binary, [:count, :nonexistent])
      assert view.count == 42
      assert view.nonexistent == nil
    end

    test "empty field list returns empty map" do
      struct = %TestCodec{ratio: 0.0}
      {:ok, binary} = TestCodec.encode(struct)

      assert {:ok, view} = TestCodec.decode_only(binary, [])
      assert view == %{}
    end

    test "decimal field projection" do
      struct = %TestCodec{price: Decimal.new("100.50"), ratio: 0.0}
      {:ok, binary} = TestCodec.encode(struct)

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

      {:ok, binary} = TestCodec.encode(struct)

      assert {:ok, view} = TestCodec.decode_only(binary, [:active, :score])
      assert view == %{active: true, score: -100}
    end

    test "returns error for truncated binary" do
      assert {:error, _} = TestCodec.decode_only(<<1, 2, 3>>, [:count])
    end

    test "returns error for empty binary" do
      assert {:error, _} = TestCodec.decode_only(<<>>, [:count])
    end
  end
end
