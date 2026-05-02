defmodule GridCodec.LifecycleHooksTest do
  use ExUnit.Case, async: true

  defmodule SnapshotCodec do
    use GridCodec.Struct,
      template_id: 19_101,
      schema_id: 191,
      version: 3,
      validate: true

    defcodec do
      field :id, :u64, presence: :required
      field :persisted_count, :u32, presence: :required

      virtual :cache, default: %{}
      virtual :decoded_header
    end

    @impl GridCodec.Struct
    def before_encode(%__MODULE__{cache: %{count: count}} = struct, _header)
        when is_integer(count) do
      %{struct | persisted_count: count}
    end

    def before_encode(%__MODULE__{} = struct, _header), do: struct

    @impl GridCodec.Struct
    def after_decode(%__MODULE__{} = struct, header) do
      {:ok,
       %{
         struct
         | cache: %{count: struct.persisted_count, header_version: header && header.version},
           decoded_header: header
       }}
    end
  end

  defmodule HookErrorCodec do
    use GridCodec.Struct, template_id: 19_102, schema_id: 191

    defcodec do
      field :id, :u64
    end

    @impl GridCodec.Struct
    def before_encode(%__MODULE__{id: 0}, _header), do: {:error, :zero_id}
    def before_encode(%__MODULE__{} = struct, _header), do: struct

    @impl GridCodec.Struct
    def after_decode(%__MODULE__{id: 13}, _header), do: {:error, :unlucky_id}
    def after_decode(%__MODULE__{} = struct, _header), do: struct
  end

  defmodule InvalidHookReturnCodec do
    use GridCodec.Struct, template_id: 19_103, schema_id: 191

    defcodec do
      field :id, :u64
    end

    @impl GridCodec.Struct
    def before_encode(%__MODULE__{}, _header), do: :not_a_struct

    @impl GridCodec.Struct
    def after_decode(%__MODULE__{}, _header), do: :not_a_struct
  end

  defmodule AfterDecodeValidatedCodec do
    use GridCodec.Struct, template_id: 19_104, schema_id: 191, validate: true

    defcodec do
      field :id, :u64
      virtual :decoded?, default: false, validate: false
    end

    validations do
      validate(&__MODULE__.must_be_after_decode/1, name: :after_decode_marker)
    end

    @impl GridCodec.Struct
    def before_encode(%__MODULE__{} = struct, _header), do: %{struct | decoded?: true}

    @impl GridCodec.Struct
    def after_decode(%__MODULE__{} = struct, _header), do: %{struct | decoded?: true}

    def must_be_after_decode(%__MODULE__{decoded?: true}), do: []

    def must_be_after_decode(_struct) do
      [
        GridCodec.ValidationError.invariant_failed(
          __MODULE__,
          :after_decode_marker,
          "after_decode/2 must run before decoded validation"
        )
      ]
    end
  end

  describe "before_encode/2" do
    test "normalizes runtime state before validation and wire encoding" do
      original = %SnapshotCodec{id: 1, persisted_count: nil, cache: %{count: 7}}

      assert {:ok, binary} = SnapshotCodec.encode(original)
      assert {:ok, decoded} = SnapshotCodec.decode(binary)

      assert decoded.persisted_count == 7
      assert decoded.cache == %{count: 7, header_version: 3}
    end

    test "receives nil header metadata for payload-only encoding" do
      original = %SnapshotCodec{id: 1, persisted_count: nil, cache: %{count: 9}}

      assert {:ok, payload} = SnapshotCodec.encode(original, header: false)
      assert {:ok, decoded} = SnapshotCodec.decode(payload, header: false)

      assert decoded.persisted_count == 9
      assert decoded.decoded_header == nil
      assert decoded.cache == %{count: 9, header_version: nil}
    end

    test "can stop encoding with a tagged error" do
      assert HookErrorCodec.encode(%HookErrorCodec{id: 0}) == {:error, :zero_id}
    end

    test "rejects invalid hook return values" do
      assert InvalidHookReturnCodec.encode(%InvalidHookReturnCodec{id: 1}) ==
               {:error, {:invalid_before_encode_return, :not_a_struct}}
    end
  end

  describe "after_decode/2" do
    test "receives header metadata for direct module decode" do
      assert {:ok, binary} =
               SnapshotCodec.encode(%SnapshotCodec{
                 id: 2,
                 persisted_count: nil,
                 cache: %{count: 11}
               })

      assert {:ok, decoded} = SnapshotCodec.decode(binary)

      assert decoded.decoded_header == %{
               block_length: SnapshotCodec.block_length(),
               template_id: 19_101,
               schema_id: 191,
               version: 3
             }
    end

    test "receives header metadata through registry dispatch" do
      GridCodec.Registry.clear_cache()

      assert {:ok, binary} =
               SnapshotCodec.encode(%SnapshotCodec{
                 id: 3,
                 persisted_count: nil,
                 cache: %{count: 12}
               })

      assert {:ok, decoded} = GridCodec.decode(binary)

      assert %SnapshotCodec{} = decoded
      assert decoded.decoded_header.version == 3
      assert decoded.cache == %{count: 12, header_version: 3}
    end

    test "can stop decoding with a tagged error" do
      assert {:ok, binary} = HookErrorCodec.encode(%HookErrorCodec{id: 13})
      assert HookErrorCodec.decode(binary) == {:error, :unlucky_id}
    end

    test "rejects invalid hook return values" do
      payload = <<1::little-64>>

      assert InvalidHookReturnCodec.decode(payload, header: false) ==
               {:error, {:invalid_after_decode_return, :not_a_struct}}
    end

    test "runs before decoded validation" do
      assert {:ok, binary} = AfterDecodeValidatedCodec.encode(%AfterDecodeValidatedCodec{id: 1})

      assert {:ok, %AfterDecodeValidatedCodec{decoded?: true}} =
               AfterDecodeValidatedCodec.decode(binary, validate: :decoded)
    end
  end

  describe "introspection" do
    test "__schema__/0 records which lifecycle hooks are present" do
      assert SnapshotCodec.__schema__().lifecycle_hooks == %{
               before_encode: true,
               after_decode: true
             }
    end
  end
end
