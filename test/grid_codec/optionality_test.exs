defmodule GridCodec.OptionalityTest do
  use ExUnit.Case, async: true

  # ============================================================================
  # Test Codecs
  # ============================================================================

  defmodule OptionalCodec do
    use GridCodec.Struct

    defcodec do
      field :id, :u64
      # default
      field :name, :u32, presence: :optional
      field :score, :u16
    end
  end

  defmodule RequiredCodec do
    use GridCodec.Struct

    defcodec do
      field :id, :u64, presence: :required
      field :count, :u32, presence: :required
    end
  end

  defmodule ConstantCodec do
    use GridCodec.Struct

    defcodec do
      field :version, :u8, presence: :constant, value: 1
      field :id, :u64
      field :type, :u16, presence: :constant, value: 42
    end
  end

  defmodule MixedCodec do
    use GridCodec.Struct

    defcodec do
      field :version, :u8, presence: :constant, value: 2
      field :id, :u64, presence: :required
      field :count, :u32, presence: :optional
      field :flags, :u8, presence: :optional, default: 0
    end
  end

  defmodule RequiredVarCodec do
    use GridCodec.Struct

    defcodec do
      field :id, :u64
      field :name, :string16, presence: :required
    end
  end

  # ============================================================================
  # Optional Field Tests (default behavior)
  # ============================================================================

  describe "optional fields (default)" do
    test "encode/decode with value" do
      data = %OptionalCodec{id: 123, name: 456, score: 789}
      {:ok, binary} = OptionalCodec.encode(data)

      {:ok, decoded} = OptionalCodec.decode(binary)

      assert decoded.id == 123
      assert decoded.name == 456
      assert decoded.score == 789
    end

    test "encode/decode with nil" do
      data = %OptionalCodec{id: 123, name: nil, score: 100}
      {:ok, binary} = OptionalCodec.encode(data)

      {:ok, decoded} = OptionalCodec.decode(binary)

      assert decoded.id == 123
      assert decoded.name == nil
      assert decoded.score == 100
    end
  end

  # ============================================================================
  # Required Field Tests
  # ============================================================================

  describe "required fields" do
    test "encode/decode with values" do
      data = %RequiredCodec{id: 100, count: 50}
      {:ok, binary} = RequiredCodec.encode(data)

      {:ok, decoded} = RequiredCodec.decode(binary)

      assert decoded.id == 100
      assert decoded.count == 50
    end

    test "encode returns error on nil value" do
      assert {:error, %GridCodec.ValidationError{}} =
               RequiredCodec.encode(%RequiredCodec{id: nil, count: 10})
    end

    test "encode returns error for second required field" do
      assert {:error, %GridCodec.ValidationError{}} =
               RequiredCodec.encode(%RequiredCodec{id: 1, count: nil})
    end

    test "new/1 returns error when required field is nil" do
      assert {:error, %GridCodec.ValidationError{code: :required_field} = err} =
               RequiredCodec.new(%{id: nil, count: 10})

      assert err.details.field == :id
    end

    test "new/1 returns error when required field is missing" do
      assert {:error, %GridCodec.ValidationError{code: :required_field} = err} =
               RequiredCodec.new(%{count: 10})

      assert err.details.field == :id
    end

    test "new/1 returns error for empty map with all required fields" do
      assert {:error, %GridCodec.ValidationError{code: :required_field}} =
               RequiredCodec.new(%{})
    end

    test "new/1 succeeds when all required fields are provided" do
      assert {:ok, %RequiredCodec{id: 42, count: 7}} = RequiredCodec.new(%{id: 42, count: 7})
    end

    test "new/1 with string keys returns error when required field is nil" do
      assert {:error, %GridCodec.ValidationError{code: :required_field}} =
               RequiredCodec.new(%{"id" => nil, "count" => 10})
    end
  end

  describe "required variable-length fields" do
    test "encode/decode with required string value" do
      data = %RequiredVarCodec{id: 123, name: "alice"}
      {:ok, binary} = RequiredVarCodec.encode(data)
      {:ok, decoded} = RequiredVarCodec.decode(binary)

      assert decoded.id == 123
      assert decoded.name == "alice"
    end

    test "encode returns error when required string is nil" do
      assert {:error, %GridCodec.ValidationError{}} =
               RequiredVarCodec.encode(%RequiredVarCodec{id: 123, name: nil})
    end

    test "new/1 returns error when required string field is missing" do
      assert {:error, %GridCodec.ValidationError{code: :required_field} = err} =
               RequiredVarCodec.new(%{id: 123})

      assert err.details.field == :name
    end
  end

  # ============================================================================
  # Constant Field Tests
  # ============================================================================

  describe "constant fields" do
    test "encode uses constant value regardless of input" do
      # Even if we pass different values, constants should be encoded as specified
      data = %ConstantCodec{version: 99, id: 12345, type: 999}
      {:ok, binary} = ConstantCodec.encode(data)

      {:ok, decoded} = ConstantCodec.decode(binary)

      # Constants should be decoded as their defined values
      assert decoded.version == 1
      assert decoded.id == 12345
      assert decoded.type == 42
    end

    test "encode works without constant field in input" do
      data = %ConstantCodec{id: 54321}
      {:ok, binary} = ConstantCodec.encode(data)

      {:ok, decoded} = ConstantCodec.decode(binary)

      assert decoded.version == 1
      assert decoded.id == 54321
      assert decoded.type == 42
    end

    test "constant fields have correct wire size" do
      data = %ConstantCodec{id: 1}
      {:ok, binary} = ConstantCodec.encode(data)

      # header (8) + version (u8) + id (u64) + type (u16) = 8 + 1 + 8 + 2 = 19 bytes
      assert byte_size(binary) == 19
    end
  end

  # ============================================================================
  # Mixed Presence Tests
  # ============================================================================

  describe "mixed presence modes" do
    test "encode/decode with all fields provided" do
      data = %MixedCodec{version: 99, id: 123, count: 456, flags: 7}
      {:ok, binary} = MixedCodec.encode(data)

      {:ok, decoded} = MixedCodec.decode(binary)

      # constant, ignores input
      assert decoded.version == 2
      assert decoded.id == 123
      assert decoded.count == 456
      assert decoded.flags == 7
    end

    test "encode/decode with optional fields nil" do
      data = %MixedCodec{id: 100, count: nil, flags: nil}
      {:ok, binary} = MixedCodec.encode(data)

      {:ok, decoded} = MixedCodec.decode(binary)

      assert decoded.version == 2
      assert decoded.id == 100
      assert decoded.count == nil
      # flags with nil encodes the null sentinel, which decodes to the declared default.
      assert decoded.flags == 0
    end

    test "required field still returns error" do
      assert {:error, %GridCodec.ValidationError{}} =
               MixedCodec.encode(%MixedCodec{id: nil, count: 10})
    end

    test "new/1 rejects nil required field but allows nil optional fields" do
      assert {:error, %GridCodec.ValidationError{code: :required_field}} =
               MixedCodec.new(%{count: 10, flags: 5})

      assert {:ok, %MixedCodec{id: 1, count: nil, flags: nil}} =
               MixedCodec.new(%{id: 1})
    end

    test "update/2 rejects setting required field to nil" do
      {:ok, existing} = MixedCodec.new(%{id: 1, count: 10})

      assert {:error, %GridCodec.ValidationError{code: :required_field}} =
               MixedCodec.update(existing, %{id: nil})
    end
  end

  # ============================================================================
  # Zero-Copy Access Tests
  # ============================================================================

  describe "zero-copy access with presence" do
    test "get macro works for constant fields" do
      require ConstantCodec

      data = %ConstantCodec{id: 999}
      {:ok, binary} = ConstantCodec.encode(data)

      assert ConstantCodec.get(binary, :version) == 1
      assert ConstantCodec.get(binary, :id) == 999
      assert ConstantCodec.get(binary, :type) == 42
    end

    test "get macro works for optional fields with nil" do
      require OptionalCodec

      data = %OptionalCodec{id: 123, name: nil, score: 100}
      {:ok, binary} = OptionalCodec.encode(data)

      assert OptionalCodec.get(binary, :id) == 123
      assert OptionalCodec.get(binary, :name) == nil
      assert OptionalCodec.get(binary, :score) == 100
    end
  end
end
