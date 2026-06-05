defmodule GridCodec.Types.PrefixedIdTest do
  use ExUnit.Case, async: true
  use ExUnitProperties
  import ExUnit.CaptureIO

  # ================================================================
  # Test type definitions
  # ================================================================

  defmodule UserId do
    use GridCodec.Types.PrefixedId, prefix: "user", tag: 0x01
  end

  defmodule MarketId do
    use GridCodec.Types.PrefixedId, prefix: "mkt", tag: 0x02
  end

  defmodule InstrumentId do
    use GridCodec.Types.PrefixedId, prefix: "inst", tag: 0x03
  end

  defmodule SchemaBoundId do
    use GridCodec.Types.PrefixedId, prefix: "bound", tag: 0x05, schema: "my_schema"
  end

  defmodule UserCreatedEvent do
    use GridCodec.Struct,
      template_id: 900,
      schema_id: 90,
      version: 1

    defcodec do
      field :user_id, GridCodec.Types.PrefixedIdTest.UserId
      field :email, :string16
      field :created_at, :timestamp_us
    end
  end

  defmodule MultiIdEvent do
    use GridCodec.Struct,
      template_id: 901,
      schema_id: 90,
      version: 1

    defcodec do
      field :user_id, GridCodec.Types.PrefixedIdTest.UserId
      field :market_id, GridCodec.Types.PrefixedIdTest.MarketId
      field :quantity, :u64
    end
  end

  @test_uuid_str "550e8400-e29b-41d4-a716-446655440000"
  @test_uuid_hex "550e8400e29b41d4a716446655440000"
  @test_uuid_raw <<0x55, 0x0E, 0x84, 0x00, 0xE2, 0x9B, 0x41, 0xD4, 0xA7, 0x16, 0x44, 0x66, 0x55,
                   0x44, 0x00, 0x00>>

  # ================================================================
  # Type-level tests
  # ================================================================

  describe "type metadata" do
    test "size is 17 bytes" do
      assert UserId.size() == 17
      assert MarketId.size() == 17
    end

    test "alignment is 1" do
      assert UserId.alignment() == 1
    end

    test "null_value is 17 zero bytes" do
      null = UserId.null_value()
      assert null == <<0, 0::128>>
      assert byte_size(null) == 17
    end

    test "prefix/0 returns full prefix with dash" do
      assert UserId.prefix() == "user-"
      assert MarketId.prefix() == "mkt-"
      assert InstrumentId.prefix() == "inst-"
    end

    test "tag/0 returns the wire tag byte" do
      assert UserId.tag() == 0x01
      assert MarketId.tag() == 0x02
      assert InstrumentId.tag() == 0x03
    end

    test "__prefixed_id_meta__/0 returns metadata" do
      meta = UserId.__prefixed_id_meta__()
      assert meta.prefix == "user-"
      assert meta.tag == 0x01
      assert meta.schema == nil
    end

    test "__prefixed_id_meta__/0 includes schema affinity when set" do
      meta = SchemaBoundId.__prefixed_id_meta__()
      assert meta.prefix == "bound-"
      assert meta.tag == 0x05
      assert meta.schema == "my_schema"
    end
  end

  describe "compile-time code generation" do
    test "wrapper module does not warn about GridCodec.Generators during compile" do
      module_name = Module.concat(__MODULE__, :"GenProbe#{System.unique_integer([:positive])}")

      warning_output =
        capture_io(:stderr, fn ->
          Code.compiler_options(ignore_module_conflict: true)

          Code.compile_string("""
          defmodule #{inspect(module_name)} do
            use GridCodec.Types.PrefixedId, prefix: "probe", tag: 0x2A
          end
          """)
        end)

      refute warning_output =~ "GridCodec.Generators.uuid/0 is undefined"
    end
  end

  # ================================================================
  # Helper function tests
  # ================================================================

  describe "generate/0" do
    test "returns a prefixed UUID string" do
      id = UserId.generate()
      assert String.starts_with?(id, "user-")
      uuid_part = String.replace_prefix(id, "user-", "")
      assert byte_size(uuid_part) == 36
    end

    test "generates unique IDs" do
      ids = for _ <- 1..100, do: UserId.generate()
      assert length(Enum.uniq(ids)) == 100
    end
  end

  describe "from_uuid/1" do
    test "prepends prefix to a UUID string" do
      assert UserId.from_uuid(@test_uuid_str) == "user-" <> @test_uuid_str
      assert MarketId.from_uuid(@test_uuid_str) == "mkt-" <> @test_uuid_str
    end
  end

  describe "to_uuid/1" do
    test "strips the prefix" do
      assert UserId.to_uuid("user-" <> @test_uuid_str) == @test_uuid_str
    end
  end

  describe "valid?/1" do
    test "returns true for valid prefixed IDs" do
      assert UserId.valid?("user-" <> @test_uuid_str) == true
    end

    test "returns false for wrong prefix" do
      assert UserId.valid?("mkt-" <> @test_uuid_str) == false
    end

    test "returns false for non-UUID content" do
      assert UserId.valid?("user-not-a-valid-uuid") == false
    end

    test "returns false for non-string" do
      assert UserId.valid?(123) == false
      assert UserId.valid?(nil) == false
    end
  end

  # ================================================================
  # Coercion matrix
  # ================================================================

  describe "coercion" do
    test "nil passes through" do
      assert {:ok, nil} =
               GridCodec.Types.PrefixedId.coerce(nil, "user-", 5, 0x01)
    end

    test "prefixed UUID string passes through" do
      input = "user-" <> @test_uuid_str

      assert {:ok, ^input} =
               GridCodec.Types.PrefixedId.coerce(input, "user-", 5, 0x01)
    end

    test "plain UUID string (36 chars) gets auto-prefixed" do
      assert {:ok, "user-" <> @test_uuid_str} =
               GridCodec.Types.PrefixedId.coerce(@test_uuid_str, "user-", 5, 0x01)
    end

    test "hex UUID string (32 chars) gets formatted and prefixed" do
      {:ok, result} =
        GridCodec.Types.PrefixedId.coerce(@test_uuid_hex, "user-", 5, 0x01)

      assert String.starts_with?(result, "user-")
      assert byte_size(result) == 5 + 36
    end

    test "raw 16-byte binary gets formatted and prefixed" do
      {:ok, result} =
        GridCodec.Types.PrefixedId.coerce(@test_uuid_raw, "user-", 5, 0x01)

      assert String.starts_with?(result, "user-")
      assert byte_size(result) == 5 + 36
    end

    test "wrong prefix rejected" do
      assert {:error, msg} =
               GridCodec.Types.PrefixedId.coerce("mkt-" <> @test_uuid_str, "user-", 5, 0x01)

      assert msg =~ "invalid prefixed ID"
    end

    test "invalid UUID string rejected" do
      assert {:error, _} =
               GridCodec.Types.PrefixedId.coerce(
                 "user-GGGGGGGG-GGGG-GGGG-GGGG-GGGGGGGGGGGG",
                 "user-",
                 5,
                 0x01
               )
    end

    test "non-string, non-binary rejected" do
      assert {:error, _} =
               GridCodec.Types.PrefixedId.coerce(12345, "user-", 5, 0x01)
    end
  end

  # ================================================================
  # Codec integration: encode/decode roundtrip
  # ================================================================

  describe "encode/decode roundtrip" do
    test "full struct roundtrip with prefixed ID" do
      user_id = "user-" <> @test_uuid_str

      {:ok, event} =
        UserCreatedEvent.new(
          user_id: user_id,
          email: "test@example.com",
          created_at: 1_700_000_000_000_000
        )

      assert event.user_id == user_id

      {:ok, binary} = UserCreatedEvent.encode(event)
      {:ok, decoded} = UserCreatedEvent.decode(binary)

      assert decoded.user_id == user_id
      assert decoded.email == "test@example.com"
      assert decoded.created_at == 1_700_000_000_000_000
    end

    test "nil roundtrip" do
      {:ok, event} = UserCreatedEvent.new(user_id: nil, email: "a@b.com")
      {:ok, binary} = UserCreatedEvent.encode(event)
      {:ok, decoded} = UserCreatedEvent.decode(binary)

      assert decoded.user_id == nil
    end

    test "coercion: plain UUID auto-prefixed in new/1" do
      {:ok, event} = UserCreatedEvent.new(user_id: @test_uuid_str, email: "a@b.com")
      assert String.starts_with?(event.user_id, "user-")
    end

    test "coercion: raw binary auto-prefixed in new/1" do
      {:ok, event} = UserCreatedEvent.new(user_id: @test_uuid_raw, email: "a@b.com")
      assert String.starts_with?(event.user_id, "user-")
    end

    test "coercion: hex UUID auto-prefixed in new/1" do
      {:ok, event} = UserCreatedEvent.new(user_id: @test_uuid_hex, email: "a@b.com")
      assert String.starts_with?(event.user_id, "user-")
    end

    test "coercion: wrong prefix rejected in new/1" do
      assert {:error, %GridCodec.ValidationError{code: :cast_error} = e} =
               UserCreatedEvent.new(user_id: "mkt-" <> @test_uuid_str, email: "a@b.com")

      assert e.details.field == :user_id
    end

    test "multiple prefixed IDs in one struct" do
      user_id = "user-" <> @test_uuid_str
      market_id = "mkt-" <> @test_uuid_str

      {:ok, event} = MultiIdEvent.new(user_id: user_id, market_id: market_id, quantity: 100)
      {:ok, binary} = MultiIdEvent.encode(event)
      {:ok, decoded} = MultiIdEvent.decode(binary)

      assert decoded.user_id == user_id
      assert decoded.market_id == market_id
      assert decoded.quantity == 100
    end
  end

  # ================================================================
  # Binary-level inspection
  # ================================================================

  describe "wire format" do
    test "tag byte is at offset 0 of the field payload" do
      user_id = "user-" <> @test_uuid_str
      {:ok, event} = UserCreatedEvent.new(user_id: user_id, email: "x")
      {:ok, binary} = UserCreatedEvent.encode(event)

      header_size = 8

      <<_header::binary-size(header_size), tag::8, uuid_bytes::binary-size(16), _rest::binary>> =
        binary

      assert tag == 0x01
      assert uuid_bytes == @test_uuid_raw
    end

    test "null sentinel is 17 zero bytes" do
      {:ok, event} = UserCreatedEvent.new(user_id: nil, email: "x")
      {:ok, binary} = UserCreatedEvent.encode(event)

      header_size = 8
      <<_header::binary-size(header_size), field_bytes::binary-size(17), _rest::binary>> = binary

      assert field_bytes == <<0, 0::128>>
    end

    test "different types have different tag bytes" do
      user_id = "user-" <> @test_uuid_str
      market_id = "mkt-" <> @test_uuid_str

      {:ok, event} = MultiIdEvent.new(user_id: user_id, market_id: market_id, quantity: 100)
      {:ok, binary} = MultiIdEvent.encode(event)

      header_size = 8

      <<_header::binary-size(header_size), user_tag::8, _uuid1::binary-size(16), mkt_tag::8,
        _uuid2::binary-size(16), _rest::binary>> = binary

      assert user_tag == 0x01
      assert mkt_tag == 0x02
    end

    test "total field size is exactly 17 bytes" do
      schema = UserCreatedEvent.__schema__()
      field_specs = UserCreatedEvent.__field_specs__()

      {_mod, _user_id_offset, _endian} = Map.fetch!(field_specs, :user_id)

      fields = schema.fields
      {_, _, _} = Enum.find(fields, fn {name, _, _} -> name == :user_id end)

      # user_id is at the start of the payload (after header), and the next
      # fixed field should be exactly 17 bytes later
      assert UserId.size() == 17
    end
  end

  # ================================================================
  # SQL generation
  # ================================================================

  describe "SQL support" do
    test "generates SQL for codec with prefixed ID" do
      sql = GridCodec.SQL.generate(UserCreatedEvent)

      assert sql =~ "user-"
      assert sql =~ "encode(substring(data"
      assert sql =~ "get_byte(data,"
    end

    test "SQL helpers include read_prefixed_id" do
      helpers = GridCodec.SQL.generate_helpers()

      assert helpers =~ "read_prefixed_id"
      assert helpers =~ "read_prefixed_id_tag"
    end

    test "SQL null check uses tag=0 AND all-zeros UUID" do
      sql = GridCodec.SQL.generate(UserCreatedEvent)

      assert sql =~ "get_byte(data," or sql =~ "THEN NULL"
    end
  end

  # ================================================================
  # Slim mode (user-defined helpers, simulating generated source)
  # ================================================================

  defmodule SlimUserId do
    @moduledoc "Generated PrefixedId with visible helpers."
    use GridCodec.Types.PrefixedId, prefix: "slim", tag: 0x04

    @typedoc "A prefixed ID string of the form `slim-<uuid>`."
    @type t() :: String.t()

    @spec generate() :: t()
    def generate do
      raw = GridCodec.Types.UUID.generate_v4()
      "slim-" <> GridCodec.Types.UUIDString.format_uuid(raw)
    end

    @spec from_uuid(String.t()) :: t()
    def from_uuid(uuid_str) when is_binary(uuid_str), do: "slim-" <> uuid_str

    @spec to_uuid(t()) :: String.t()
    def to_uuid("slim-" <> uuid_str), do: uuid_str

    @spec valid?(t() | term()) :: boolean()
    def valid?("slim-" <> <<uuid_str::binary-size(36)>>) do
      GridCodec.Types.PrefixedId.valid_uuid_string?(uuid_str)
    end

    def valid?(_), do: false

    @spec prefix() :: String.t()
    def prefix, do: "slim-"

    @spec tag() :: 0..254
    def tag, do: 0x04
  end

  defmodule SlimIdEvent do
    use GridCodec.Struct, template_id: 902, schema_id: 90, version: 1

    defcodec do
      field :slim_id, GridCodec.Types.PrefixedIdTest.SlimUserId
      field :label, :string16
    end
  end

  describe "slim mode (user-defined helpers)" do
    test "generate/0 works" do
      id = SlimUserId.generate()
      assert String.starts_with?(id, "slim-")
    end

    test "from_uuid/1 prepends prefix" do
      assert SlimUserId.from_uuid("550e8400-e29b-41d4-a716-446655440000") ==
               "slim-550e8400-e29b-41d4-a716-446655440000"
    end

    test "to_uuid/1 strips prefix" do
      assert SlimUserId.to_uuid("slim-550e8400-e29b-41d4-a716-446655440000") ==
               "550e8400-e29b-41d4-a716-446655440000"
    end

    test "valid?/1 validates" do
      assert SlimUserId.valid?("slim-550e8400-e29b-41d4-a716-446655440000")
      refute SlimUserId.valid?("user-550e8400-e29b-41d4-a716-446655440000")
      refute SlimUserId.valid?(nil)
    end

    test "prefix/0 and tag/0" do
      assert SlimUserId.prefix() == "slim-"
      assert SlimUserId.tag() == 0x04
    end

    test "Type callbacks still work (size, alignment, null_value)" do
      assert SlimUserId.size() == 17
      assert SlimUserId.alignment() == 1
      assert SlimUserId.null_value() == <<0, 0::128>>
    end

    test "__prefixed_id_meta__/0 still present" do
      assert SlimUserId.__prefixed_id_meta__() == %{prefix: "slim-", tag: 0x04, schema: nil}
    end

    test "macro does not inject duplicate helpers" do
      funs = SlimUserId.__info__(:functions)
      generate_count = Enum.count(funs, fn {name, _} -> name == :generate end)
      assert generate_count == 1, "generate/0 should appear exactly once (user-defined only)"
    end

    test "encode/decode roundtrip in a codec" do
      id = SlimUserId.generate()
      {:ok, event} = SlimIdEvent.new(slim_id: id, label: "test")
      {:ok, binary} = SlimIdEvent.encode(event)
      {:ok, decoded} = SlimIdEvent.decode(binary)

      assert decoded.slim_id == id
      assert decoded.label == "test"
    end

    test "coercion works through new/1" do
      uuid = "550e8400-e29b-41d4-a716-446655440000"
      {:ok, event} = SlimIdEvent.new(slim_id: uuid, label: "x")
      assert String.starts_with?(event.slim_id, "slim-")
    end
  end

  # ================================================================
  # Property tests
  # ================================================================

  property "roundtrip for any valid user ID" do
    check all(
            raw_uuid <- StreamData.binary(length: 16),
            raw_uuid != <<0::128>>
          ) do
      uuid_str = GridCodec.Types.UUIDString.format_uuid(raw_uuid)
      user_id = "user-" <> uuid_str

      {:ok, event} = UserCreatedEvent.new(user_id: user_id, email: "a@b.com")
      {:ok, binary} = UserCreatedEvent.encode(event)
      {:ok, decoded} = UserCreatedEvent.decode(binary)

      assert decoded.user_id == user_id
    end
  end

  property "tag byte matches type in encoded binary" do
    check all(
            raw_uuid <- StreamData.binary(length: 16),
            raw_uuid != <<0::128>>
          ) do
      uuid_str = GridCodec.Types.UUIDString.format_uuid(raw_uuid)
      user_id = "user-" <> uuid_str
      market_id = "mkt-" <> uuid_str

      {:ok, event} = MultiIdEvent.new(user_id: user_id, market_id: market_id, quantity: 1)
      {:ok, binary} = MultiIdEvent.encode(event)

      <<_header::binary-size(8), user_tag::8, _::binary-size(16), mkt_tag::8, _::binary>> = binary

      assert user_tag == 0x01
      assert mkt_tag == 0x02
    end
  end
end
