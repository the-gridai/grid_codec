defmodule GridCodec.RequiredDecodeTest do
  @moduledoc """
  Exercises the decode-time enforcement of `presence: :required`.

  The core contract: a `:required` field's decoded value must never be `nil`.
  When a shorter historical payload is padded from the type's null sentinel
  (see `decode_versioned_payload/2`), or when a new-encoding places a
  sentinel-equivalent value in a required slot, the decoder:

    * substitutes the declared `:default` if one is provided, or
    * returns `{:error, {:required_field_absent, field}}` if no default exists.

  This holds uniformly across built-in types (integers, decimals, uuids) and
  for custom types that define a `decode_value_ast/1` null mapping. Types
  that never surface `nil` (no `decode_value_ast/1`) are unaffected because
  the nil branch is unreachable.
  """

  use ExUnit.Case, async: true

  # ============================================================================
  # V1 baseline: a single u64 id field. Shared as the "historical" writer
  # across every scenario below.
  # ============================================================================

  defmodule V1 do
    @moduledoc false
    use GridCodec.Struct,
      template_id: 9_100,
      schema_id: 91,
      version: 1,
      field_defaults: [presence: :required]

    defcodec do
      field :id, :u64
    end
  end

  # ============================================================================
  # V2 readers: same template_id/schema_id, but each appends a new required
  # field with a distinct strategy. Decoding a V1-encoded binary through each
  # V2 reader exercises the null-padding path on that field's type.
  # ============================================================================

  defmodule V2U32RequiredNoDefault do
    @moduledoc false
    use GridCodec.Struct,
      template_id: 9_100,
      schema_id: 91,
      version: 2,
      field_defaults: [presence: :required]

    defcodec do
      field :id, :u64
      field :counter, :u32, since: 2
    end
  end

  defmodule V2U32RequiredWithDefault do
    @moduledoc false
    use GridCodec.Struct,
      template_id: 9_100,
      schema_id: 91,
      version: 2,
      field_defaults: [presence: :required]

    defcodec do
      field :id, :u64
      field :counter, :u32, since: 2, default: 42
    end
  end

  defmodule V2DecimalRequiredNoDefault do
    @moduledoc false
    use GridCodec.Struct,
      template_id: 9_100,
      schema_id: 91,
      version: 2,
      field_defaults: [presence: :required]

    defcodec do
      field :id, :u64
      field :price, {:decimal, scale: 8}, wire_format: :i64, since: 2
    end
  end

  defmodule V2DecimalRequiredWithDefault do
    @moduledoc false
    use GridCodec.Struct,
      template_id: 9_100,
      schema_id: 91,
      version: 2,
      field_defaults: [presence: :required]

    defcodec do
      field :id, :u64

      field :price, {:decimal, scale: 8},
        wire_format: :i64,
        since: 2,
        default: Decimal.new("1.00000000")
    end
  end

  defmodule V2UUIDRequiredWithDefault do
    @moduledoc false
    use GridCodec.Struct,
      template_id: 9_100,
      schema_id: 91,
      version: 2,
      field_defaults: [presence: :required]

    defcodec do
      field :id, :u64
      field :tid, :uuid, since: 2, default: <<0xCA, 0xFE, 0xBA, 0xBE, 0::96>>
    end
  end

  defmodule V2Optional do
    @moduledoc false
    use GridCodec.Struct,
      template_id: 9_100,
      schema_id: 91,
      version: 2

    defcodec do
      field :id, :u64
      field :counter, :u32, since: 2
    end
  end

  # A bool required field with a concrete default — bool DOES export
  # `decode_value_ast/1` (it maps 0xFF to nil), so the required-check is
  # active and the default path applies.
  defmodule V2BoolRequiredWithDefault do
    @moduledoc false
    use GridCodec.Struct,
      template_id: 9_100,
      schema_id: 91,
      version: 2,
      field_defaults: [presence: :required]

    defcodec do
      field :id, :u64
      field :flag, :bool, since: 2, default: false
    end
  end

  defmodule V2StringRequiredNoDefault do
    @moduledoc false
    use GridCodec.Struct,
      template_id: 9_100,
      schema_id: 91,
      version: 2,
      field_defaults: [presence: :required]

    defcodec do
      field :id, :u64
      field :note, :string16, since: 2
    end
  end

  defmodule V2StringRequiredWithDefault do
    @moduledoc false
    use GridCodec.Struct,
      template_id: 9_100,
      schema_id: 91,
      version: 2,
      field_defaults: [presence: :required]

    defcodec do
      field :id, :u64
      field :note, :string16, since: 2, default: "legacy"
    end
  end

  setup_all do
    {:ok, v1_binary} = V1.encode(%V1{id: 42})
    {:ok, v1_binary: v1_binary}
  end

  # ============================================================================
  # No default + null-sentinel padding → structured error
  # ============================================================================

  describe "required field without :default (historical padding)" do
    test "u32: historical decode returns {:error, {:required_field_absent, :counter}}",
         %{v1_binary: v1} do
      assert {:error, {:required_field_absent, :counter}} =
               V2U32RequiredNoDefault.decode(v1)
    end

    test "decimal (i64-backed): same structured error", %{v1_binary: v1} do
      assert {:error, {:required_field_absent, :price}} =
               V2DecimalRequiredNoDefault.decode(v1)
    end

    test "error names the specific field", %{v1_binary: v1} do
      assert {:error, {:required_field_absent, field}} =
               V2DecimalRequiredNoDefault.decode(v1)

      assert field == :price
    end

    test "string16: missing appended var-data returns structured error", %{v1_binary: v1} do
      assert {:error, {:required_field_absent, :note}} =
               V2StringRequiredNoDefault.decode(v1)
    end
  end

  # ============================================================================
  # With default → substitute, round-trippable
  # ============================================================================

  describe "required field with :default (historical padding)" do
    test "u32: counter decodes to declared default", %{v1_binary: v1} do
      assert {:ok, %V2U32RequiredWithDefault{id: 42, counter: 42}} =
               V2U32RequiredWithDefault.decode(v1)
    end

    test "decimal: price decodes to declared default", %{v1_binary: v1} do
      assert {:ok, decoded} = V2DecimalRequiredWithDefault.decode(v1)
      assert decoded.id == 42
      assert Decimal.equal?(decoded.price, Decimal.new("1.00000000"))
    end

    test "uuid: tid decodes to declared default", %{v1_binary: v1} do
      assert {:ok, %V2UUIDRequiredWithDefault{id: 42, tid: tid}} =
               V2UUIDRequiredWithDefault.decode(v1)

      assert tid == <<0xCA, 0xFE, 0xBA, 0xBE, 0::96>>
    end

    test "string16: missing appended var-data decodes to declared default",
         %{v1_binary: v1} do
      assert {:ok, %V2StringRequiredWithDefault{id: 42, note: "legacy"}} =
               V2StringRequiredWithDefault.decode(v1)
    end

    test "decoded struct round-trips cleanly (encode → decode is stable)",
         %{v1_binary: v1} do
      {:ok, once} = V2U32RequiredWithDefault.decode(v1)
      {:ok, reencoded} = V2U32RequiredWithDefault.encode(once)
      {:ok, twice} = V2U32RequiredWithDefault.decode(reencoded)

      assert twice == once
    end
  end

  # ============================================================================
  # New-encoding: sentinel-valued required field still rejected
  # ============================================================================

  # A twin V2 writer in :optional mode (same template_id / schema_id /
  # version / field layout) lets us produce a "current, full-length" payload
  # whose counter slot carries the u32 null sentinel — simulating what any
  # producer would emit if it legitimately wrote nil for an optional field
  # and a newer consumer then read it as required.
  defmodule V2U32OptionalWriter do
    @moduledoc false
    use GridCodec.Struct,
      template_id: 9_100,
      schema_id: 91,
      version: 2

    defcodec do
      field :id, :u64
      field :counter, :u32, since: 2
    end
  end

  describe "sentinel-valued required field in a current payload" do
    test "a null-sentinel u32 in the counter slot errors on decode (not just on historical padding)" do
      {:ok, bin} = V2U32OptionalWriter.encode(%V2U32OptionalWriter{id: 7, counter: nil})

      assert {:error, {:required_field_absent, :counter}} =
               V2U32RequiredNoDefault.decode(bin)
    end

    test "the same binary decodes successfully when :default is declared" do
      {:ok, bin} = V2U32OptionalWriter.encode(%V2U32OptionalWriter{id: 7, counter: nil})

      assert {:ok, %V2U32RequiredWithDefault{id: 7, counter: 42}} =
               V2U32RequiredWithDefault.decode(bin)
    end
  end

  # ============================================================================
  # Optional fields and "nil-free" types are unaffected
  # ============================================================================

  describe "unchanged behavior" do
    test ":optional required-adjacent field still decodes to nil for historical data",
         %{v1_binary: v1} do
      assert {:ok, %V2Optional{id: 42, counter: nil}} =
               V2Optional.decode(v1)
    end

    test "bool: required with default decodes historical payloads to the default",
         %{v1_binary: v1} do
      # The `:bool` type module exports `decode_value_ast/1` (0xFF → nil),
      # so the required-check is active — without a default this would
      # error; with `default: false` it substitutes cleanly.
      assert {:ok, %V2BoolRequiredWithDefault{id: 42, flag: false}} =
               V2BoolRequiredWithDefault.decode(v1)
    end

    test "current (non-historical) encode/decode roundtrips unaffected" do
      s = %V2U32RequiredNoDefault{id: 1, counter: 7}
      {:ok, bin} = V2U32RequiredNoDefault.encode(s)
      assert {:ok, ^s} = V2U32RequiredNoDefault.decode(bin)
    end
  end

  # ============================================================================
  # Custom-type shape note
  #
  # The required-wrapper emits `case value_ast do nil -> ...; v -> v end`.
  # When the field's type module does not export `decode_value_ast/1`, the
  # compiler passes the raw pattern-matched var through untouched. For a
  # fixed-size binary pattern (`<<v::binary-size(n)>>`) or an integer
  # binding, that var is never `nil` at runtime, so the `nil` branch is
  # statically unreachable — Elixir 1.19's type checker in fact surfaces
  # this as an "unreachable clause" warning for such types, which is the
  # strongest possible evidence that the wrapper is a zero-cost no-op on
  # them. This property covers consumer-style user-defined types that
  # wrap a fixed-size opaque payload without a distinguished null sentinel.
  # ============================================================================
end
