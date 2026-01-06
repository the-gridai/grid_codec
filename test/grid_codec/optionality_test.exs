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

  # ============================================================================
  # Optional Field Tests (default behavior)
  # ============================================================================

  describe "optional fields (default)" do
    test "encode/decode with value" do
      data = %OptionalCodec{id: 123, name: 456, score: 789}
      binary = OptionalCodec.encode(data)

      {:ok, decoded} = OptionalCodec.decode(binary)

      assert decoded.id == 123
      assert decoded.name == 456
      assert decoded.score == 789
    end

    test "encode/decode with nil" do
      data = %OptionalCodec{id: 123, name: nil, score: 100}
      binary = OptionalCodec.encode(data)

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
      binary = RequiredCodec.encode(data)

      {:ok, decoded} = RequiredCodec.decode(binary)

      assert decoded.id == 100
      assert decoded.count == 50
    end

    test "encode raises on nil value" do
      assert_raise ArgumentError, ~r/required field :id cannot be nil/, fn ->
        RequiredCodec.encode(%RequiredCodec{id: nil, count: 10})
      end
    end

    test "encode raises for second required field" do
      assert_raise ArgumentError, ~r/required field :count cannot be nil/, fn ->
        RequiredCodec.encode(%RequiredCodec{id: 1, count: nil})
      end
    end
  end

  # ============================================================================
  # Constant Field Tests
  # ============================================================================

  describe "constant fields" do
    test "encode uses constant value regardless of input" do
      # Even if we pass different values, constants should be encoded as specified
      data = %ConstantCodec{version: 99, id: 12345, type: 999}
      binary = ConstantCodec.encode(data)

      {:ok, decoded} = ConstantCodec.decode(binary)

      # Constants should be decoded as their defined values
      assert decoded.version == 1
      assert decoded.id == 12345
      assert decoded.type == 42
    end

    test "encode works without constant field in input" do
      data = %ConstantCodec{id: 54321}
      binary = ConstantCodec.encode(data)

      {:ok, decoded} = ConstantCodec.decode(binary)

      assert decoded.version == 1
      assert decoded.id == 54321
      assert decoded.type == 42
    end

    test "constant fields have correct wire size" do
      data = %ConstantCodec{id: 1}
      binary = ConstantCodec.encode(data)

      # version (u8) + id (u64) + type (u16) = 1 + 8 + 2 = 11 bytes
      assert byte_size(binary) == 11
    end
  end

  # ============================================================================
  # Mixed Presence Tests
  # ============================================================================

  describe "mixed presence modes" do
    test "encode/decode with all fields provided" do
      data = %MixedCodec{version: 99, id: 123, count: 456, flags: 7}
      binary = MixedCodec.encode(data)

      {:ok, decoded} = MixedCodec.decode(binary)

      # constant, ignores input
      assert decoded.version == 2
      assert decoded.id == 123
      assert decoded.count == 456
      assert decoded.flags == 7
    end

    test "encode/decode with optional fields nil" do
      data = %MixedCodec{id: 100, count: nil, flags: nil}
      binary = MixedCodec.encode(data)

      {:ok, decoded} = MixedCodec.decode(binary)

      assert decoded.version == 2
      assert decoded.id == 100
      assert decoded.count == nil
      # flags with nil encodes as nil (0 is default when field is omitted from map)
      assert decoded.flags == nil
    end

    test "required field still raises" do
      assert_raise ArgumentError, ~r/required field :id cannot be nil/, fn ->
        MixedCodec.encode(%MixedCodec{id: nil, count: 10})
      end
    end
  end

  # ============================================================================
  # Zero-Copy Access Tests
  # ============================================================================

  describe "zero-copy access with presence" do
    test "get works for constant fields" do
      data = %ConstantCodec{id: 999}
      binary = ConstantCodec.encode(data)
      env = ConstantCodec.wrap(binary)

      assert ConstantCodec.get(env, :version) == 1
      assert ConstantCodec.get(env, :id) == 999
      assert ConstantCodec.get(env, :type) == 42
    end

    test "get works for optional fields with nil" do
      data = %OptionalCodec{id: 123, name: nil, score: 100}
      binary = OptionalCodec.encode(data)
      env = OptionalCodec.wrap(binary)

      assert OptionalCodec.get(env, :id) == 123
      assert OptionalCodec.get(env, :name) == nil
      assert OptionalCodec.get(env, :score) == 100
    end
  end
end
