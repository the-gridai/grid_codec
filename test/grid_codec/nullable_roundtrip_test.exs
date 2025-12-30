defmodule GridCodec.NullableRoundtripTest do
  @moduledoc """
  Tests for safe roundtrip serialization of:
  - All nullable types with nil values
  - Empty fields (empty strings, empty groups, etc.)

  This ensures that null sentinels and empty values are correctly
  encoded and decoded without data loss or corruption.
  """
  use ExUnit.Case, async: true

  # ============================================================================
  # Test Type Definitions
  # ============================================================================

  defmodule TestEnums do
    defmodule Status do
      use GridCodec.Types.Enum, encoding: :u8

      defenum do
        value(:pending, 0)
        value(:active, 1)
      end
    end

    defmodule Priority do
      use GridCodec.Types.Enum, encoding: :u16

      defenum do
        value(:low, 0)
        value(:high, 1)
      end
    end
  end

  defmodule TestCharArray do
    use GridCodec.Types.CharArray, length: 16
  end

  defmodule TestBitset do
    use GridCodec.Types.Bitset, size: :u8
    flag(:read, 0)
    flag(:write, 1)
  end

  # ============================================================================
  # Codec Definitions for Testing
  # ============================================================================

  defmodule AllNullableCodec do
    @moduledoc "Codec with all nullable fixed-size types"
    use GridCodec,
      types: [
        status: GridCodec.NullableRoundtripTest.TestEnums.Status,
        priority: GridCodec.NullableRoundtripTest.TestEnums.Priority,
        symbol: GridCodec.NullableRoundtripTest.TestCharArray,
        flags: GridCodec.NullableRoundtripTest.TestBitset
      ]

    defcodec do
      # Unsigned integers (null = max value)
      field(:u8_val, :u8)
      field(:u16_val, :u16)
      field(:u32_val, :u32)
      field(:u64_val, :u64)

      # Signed integers (null = min value)
      field(:i8_val, :i8)
      field(:i16_val, :i16)
      field(:i32_val, :i32)
      field(:i64_val, :i64)

      # Bool (null = 255)
      field(:bool_val, :bool)

      # UUID (null = all zeros)
      field(:uuid_val, :uuid)

      # Timestamps (null = min i64)
      field(:timestamp_us, :timestamp_us)
      field(:timestamp_ns, :timestamp_ns)

      # Decimal (null = min mantissa)
      field(:decimal_val, :decimal)

      # Enum (null = max encoding value)
      field(:status, :status)
      field(:priority, :priority)

      # Char array (null = all zeros -> empty string)
      field(:symbol, :symbol)

      # Bitset (nil -> empty set)
      field(:flags, :flags)
    end
  end

  defmodule EmptyStringsCodec do
    @moduledoc "Codec with variable-length string types"
    use GridCodec

    defcodec do
      field(:id, :u64)
      field(:name, :string8)
      field(:description, :string16)
      field(:content, :string32)
    end
  end

  # Note: Groups with inline field definitions are not yet fully implemented
  # in the defcodec DSL. Entry encoders/decoders are not auto-generated.
  # To use groups, you must provide a pre-defined entry codec module.
  # See GridCodec.Group documentation for manual group handling.

  defmodule MixedCodec do
    @moduledoc "Codec with fixed fields and variable strings (no groups)"
    use GridCodec,
      types: [
        status: GridCodec.NullableRoundtripTest.TestEnums.Status
      ]

    defcodec do
      field(:id, :uuid)
      field(:count, :u32)
      field(:status, :status)
      field(:active, :bool)
      field(:name, :string16)
      field(:notes, :string16)
    end
  end

  # ============================================================================
  # Tests: All Nullable Types with nil
  # ============================================================================

  describe "nullable types roundtrip with nil" do
    test "all nullable fixed types encode/decode nil correctly" do
      data = %{
        u8_val: nil,
        u16_val: nil,
        u32_val: nil,
        u64_val: nil,
        i8_val: nil,
        i16_val: nil,
        i32_val: nil,
        i64_val: nil,
        bool_val: nil,
        uuid_val: nil,
        timestamp_us: nil,
        timestamp_ns: nil,
        decimal_val: nil,
        status: nil,
        priority: nil,
        symbol: nil,
        flags: nil
      }

      binary = AllNullableCodec.encode(data)
      {:ok, decoded} = AllNullableCodec.decode(binary)

      # All integer types should be nil
      assert decoded.u8_val == nil, "u8 nil failed"
      assert decoded.u16_val == nil, "u16 nil failed"
      assert decoded.u32_val == nil, "u32 nil failed"
      assert decoded.u64_val == nil, "u64 nil failed"
      assert decoded.i8_val == nil, "i8 nil failed"
      assert decoded.i16_val == nil, "i16 nil failed"
      assert decoded.i32_val == nil, "i32 nil failed"
      assert decoded.i64_val == nil, "i64 nil failed"

      # Bool should be nil
      assert decoded.bool_val == nil, "bool nil failed"

      # UUID should be nil (all-zeros decoded to nil)
      assert decoded.uuid_val == nil, "uuid nil failed"

      # Timestamps should be nil
      assert decoded.timestamp_us == nil, "timestamp_us nil failed"
      assert decoded.timestamp_ns == nil, "timestamp_ns nil failed"

      # Decimal should be nil
      assert decoded.decimal_val == nil, "decimal nil failed"

      # Enums should be nil
      assert decoded.status == nil, "status enum nil failed"
      assert decoded.priority == nil, "priority enum nil failed"

      # Char array nil becomes empty string
      assert decoded.symbol == "" or decoded.symbol == nil, "symbol nil failed"

      # Bitset nil becomes empty MapSet
      assert decoded.flags == MapSet.new() or decoded.flags == nil, "flags nil failed"
    end

    test "mixed nil and non-nil values roundtrip" do
      data = %{
        u8_val: 100,
        u16_val: nil,
        u32_val: 12345,
        u64_val: nil,
        i8_val: -50,
        i16_val: nil,
        i32_val: nil,
        i64_val: -9000,
        bool_val: true,
        uuid_val: nil,
        timestamp_us: System.system_time(:microsecond),
        timestamp_ns: nil,
        decimal_val: Decimal.new("123.45"),
        status: :active,
        priority: nil,
        symbol: "TEST",
        flags: MapSet.new([:read])
      }

      binary = AllNullableCodec.encode(data)
      {:ok, decoded} = AllNullableCodec.decode(binary)

      assert decoded.u8_val == 100
      assert decoded.u16_val == nil
      assert decoded.u32_val == 12345
      assert decoded.u64_val == nil
      assert decoded.i8_val == -50
      assert decoded.i16_val == nil
      assert decoded.i32_val == nil
      assert decoded.i64_val == -9000
      assert decoded.bool_val == true
      assert decoded.uuid_val == nil
      assert decoded.timestamp_us == data.timestamp_us
      assert decoded.timestamp_ns == nil
      assert Decimal.equal?(decoded.decimal_val, data.decimal_val)
      assert decoded.status == :active
      assert decoded.priority == nil
      assert decoded.symbol == "TEST"
      assert MapSet.equal?(decoded.flags, MapSet.new([:read]))
    end
  end

  # ============================================================================
  # Tests: Empty Strings
  # ============================================================================

  describe "empty strings roundtrip" do
    # Note: GridCodec uses length=0 for both nil and empty strings
    # So empty strings decode as nil (this is by design for simplicity)

    test "empty string8 encodes as nil" do
      data = %{id: 123, name: "", description: "test", content: "test"}
      binary = EmptyStringsCodec.encode(data)
      {:ok, decoded} = EmptyStringsCodec.decode(binary)

      # Empty strings encode with length 0, decode as nil
      assert decoded.name == nil
    end

    test "empty string16 encodes as nil" do
      data = %{id: 123, name: "test", description: "", content: "test"}
      binary = EmptyStringsCodec.encode(data)
      {:ok, decoded} = EmptyStringsCodec.decode(binary)

      # Empty strings encode with length 0, decode as nil
      assert decoded.description == nil
    end

    test "empty string32 encodes as nil" do
      data = %{id: 123, name: "test", description: "test", content: ""}
      binary = EmptyStringsCodec.encode(data)
      {:ok, decoded} = EmptyStringsCodec.decode(binary)

      # Empty strings encode with length 0, decode as nil
      assert decoded.content == nil
    end

    test "all empty strings encode as nil" do
      data = %{id: 456, name: "", description: "", content: ""}
      binary = EmptyStringsCodec.encode(data)
      {:ok, decoded} = EmptyStringsCodec.decode(binary)

      assert decoded.id == 456
      # All empty strings become nil after decode
      assert decoded.name == nil
      assert decoded.description == nil
      assert decoded.content == nil
    end

    test "nil strings encode same as empty" do
      data = %{id: 789, name: nil, description: nil, content: nil}
      binary = EmptyStringsCodec.encode(data)
      {:ok, decoded} = EmptyStringsCodec.decode(binary)

      assert decoded.id == 789
      # nil strings encode as length 0, decode as nil
      assert decoded.name == nil
      assert decoded.description == nil
      assert decoded.content == nil
    end

    test "non-empty strings roundtrip correctly" do
      data = %{id: 999, name: "hello", description: "world", content: "test123"}
      binary = EmptyStringsCodec.encode(data)
      {:ok, decoded} = EmptyStringsCodec.decode(binary)

      assert decoded.id == 999
      assert decoded.name == "hello"
      assert decoded.description == "world"
      assert decoded.content == "test123"
    end
  end

  # ============================================================================
  # Tests: Groups (Manual API)
  # ============================================================================

  describe "groups with manual API" do
    # Groups via defcodec DSL are not fully implemented - entry encoders
    # are not auto-generated. Use GridCodec.Group module directly.

    test "empty group encodes/decodes via manual API" do
      entries = []
      entry_encoder = fn _entry -> <<>> end
      entry_decoder = fn _binary -> %{} end

      binary = GridCodec.Group.encode(entries, entry_encoder)

      # Empty group: blockLength=0, numInGroup=0
      assert binary == <<0::little-16, 0::little-16>>

      {:ok, group} = GridCodec.Group.parse(binary, entry_decoder)
      assert GridCodec.Group.count(group) == 0
    end

    test "group with entries encodes/decodes via manual API" do
      entries = [%{item_id: 1, qty: 10}, %{item_id: 2, qty: 20}]

      entry_encoder = fn %{item_id: id, qty: qty} ->
        <<id::little-32, qty::little-16>>
      end

      entry_decoder = fn <<id::little-32, qty::little-16>> ->
        %{item_id: id, qty: qty}
      end

      binary = GridCodec.Group.encode(entries, entry_encoder)

      # Header: blockLength=6 (4+2 bytes), numInGroup=2
      assert <<6::little-16, 2::little-16, _rest::binary>> = binary

      {:ok, group} = GridCodec.Group.parse(binary, entry_decoder)
      assert GridCodec.Group.count(group) == 2

      # get_entry returns the decoded entry directly (not wrapped in {:ok, ...})
      entry0 = GridCodec.Group.get_entry(group, 0)
      assert entry0.item_id == 1
      assert entry0.qty == 10

      entry1 = GridCodec.Group.get_entry(group, 1)
      assert entry1.item_id == 2
      assert entry1.qty == 20
    end
  end

  # ============================================================================
  # Tests: Mixed Empty/Null Fields
  # ============================================================================

  describe "mixed codec with all empty/null fields" do
    test "all fields empty/null roundtrips" do
      data = %{
        id: nil,
        count: nil,
        status: nil,
        active: nil,
        name: "",
        notes: nil
      }

      binary = MixedCodec.encode(data)
      {:ok, decoded} = MixedCodec.decode(binary)

      assert decoded.id == nil
      assert decoded.count == nil
      assert decoded.status == nil
      assert decoded.active == nil
      # Empty strings encode as length 0, decode as nil
      assert decoded.name == nil
      assert decoded.notes == nil
    end

    test "alternating empty/populated fields" do
      uuid = :crypto.strong_rand_bytes(16)

      data = %{
        id: uuid,
        count: nil,
        status: :pending,
        active: nil,
        name: "",
        notes: "Some notes"
      }

      binary = MixedCodec.encode(data)
      {:ok, decoded} = MixedCodec.decode(binary)

      assert decoded.id == uuid
      assert decoded.count == nil
      assert decoded.status == :pending
      assert decoded.active == nil
      # Empty string encodes as nil
      assert decoded.name == nil
      assert decoded.notes == "Some notes"
    end
  end

  # ============================================================================
  # Tests: Zero-Copy Access for Null Values
  # ============================================================================

  describe "zero-copy get with null values" do
    test "get returns nil for null fields" do
      data = %{
        u8_val: nil,
        u16_val: nil,
        u32_val: nil,
        u64_val: nil,
        i8_val: nil,
        i16_val: nil,
        i32_val: nil,
        i64_val: nil,
        bool_val: nil,
        uuid_val: nil,
        timestamp_us: nil,
        timestamp_ns: nil,
        decimal_val: nil,
        status: nil,
        priority: nil,
        symbol: nil,
        flags: nil
      }

      binary = AllNullableCodec.encode(data)
      env = AllNullableCodec.wrap(binary)

      assert AllNullableCodec.get(env, :u8_val) == nil
      assert AllNullableCodec.get(env, :u64_val) == nil
      assert AllNullableCodec.get(env, :i32_val) == nil
      assert AllNullableCodec.get(env, :bool_val) == nil
      assert AllNullableCodec.get(env, :uuid_val) == nil
      assert AllNullableCodec.get(env, :timestamp_us) == nil
      assert AllNullableCodec.get(env, :decimal_val) == nil
      assert AllNullableCodec.get(env, :status) == nil
    end
  end

  # ============================================================================
  # Tests: Boundary Values
  # ============================================================================

  describe "boundary values near null sentinels" do
    test "values just below null sentinel roundtrip" do
      # These are the maximum valid values (null sentinels - 1)
      data = %{
        u8_val: 254,
        u16_val: 65_534,
        u32_val: 4_294_967_294,
        u64_val: 18_446_744_073_709_551_614,
        i8_val: 127,
        i16_val: 32_767,
        i32_val: 2_147_483_647,
        i64_val: 9_223_372_036_854_775_807,
        bool_val: true,
        uuid_val:
          <<255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255>>,
        timestamp_us: 9_223_372_036_854_775_807,
        timestamp_ns: 9_223_372_036_854_775_807,
        decimal_val: Decimal.new("999999999999999999"),
        status: :active,
        priority: :high,
        symbol: "MAXVALUE",
        flags: MapSet.new([:read, :write])
      }

      binary = AllNullableCodec.encode(data)
      {:ok, decoded} = AllNullableCodec.decode(binary)

      assert decoded.u8_val == 254
      assert decoded.u16_val == 65_534
      assert decoded.u32_val == 4_294_967_294
      assert decoded.u64_val == 18_446_744_073_709_551_614
      assert decoded.i8_val == 127
      assert decoded.i16_val == 32_767
      assert decoded.i32_val == 2_147_483_647
      assert decoded.i64_val == 9_223_372_036_854_775_807
      assert decoded.bool_val == true
      # Non-zero UUID should roundtrip
      assert decoded.uuid_val == data.uuid_val
    end

    test "minimum valid signed values roundtrip" do
      data = %{
        u8_val: 0,
        u16_val: 0,
        u32_val: 0,
        u64_val: 0,
        i8_val: -127,
        i16_val: -32_767,
        i32_val: -2_147_483_647,
        i64_val: -9_223_372_036_854_775_807,
        bool_val: false,
        uuid_val: <<1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0>>,
        timestamp_us: -9_223_372_036_854_775_807,
        timestamp_ns: -9_223_372_036_854_775_807,
        decimal_val: Decimal.new("-999999999999999999"),
        status: :pending,
        priority: :low,
        symbol: "",
        flags: MapSet.new()
      }

      binary = AllNullableCodec.encode(data)
      {:ok, decoded} = AllNullableCodec.decode(binary)

      assert decoded.u8_val == 0
      assert decoded.i8_val == -127
      assert decoded.i64_val == -9_223_372_036_854_775_807
      assert decoded.bool_val == false
      assert decoded.uuid_val == data.uuid_val
    end
  end

  # ============================================================================
  # Tests: Determinism
  # ============================================================================

  describe "encoding determinism" do
    test "encoding nil produces same binary every time" do
      data = %{
        u8_val: nil,
        u16_val: nil,
        u32_val: nil,
        u64_val: nil,
        i8_val: nil,
        i16_val: nil,
        i32_val: nil,
        i64_val: nil,
        bool_val: nil,
        uuid_val: nil,
        timestamp_us: nil,
        timestamp_ns: nil,
        decimal_val: nil,
        status: nil,
        priority: nil,
        symbol: nil,
        flags: nil
      }

      binary1 = AllNullableCodec.encode(data)
      binary2 = AllNullableCodec.encode(data)
      binary3 = AllNullableCodec.encode(data)

      assert binary1 == binary2
      assert binary2 == binary3
    end

    test "encoding empty strings/groups produces same binary" do
      data = %{
        id: nil,
        count: nil,
        status: nil,
        active: nil,
        entries: [],
        name: "",
        notes: ""
      }

      binary1 = MixedCodec.encode(data)
      binary2 = MixedCodec.encode(data)

      assert binary1 == binary2
    end
  end
end
