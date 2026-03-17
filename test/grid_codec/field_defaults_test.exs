defmodule GridCodec.FieldDefaultsTest do
  use ExUnit.Case, async: true

  # ============================================================================
  # Test Codecs
  # ============================================================================

  defmodule AllRequired do
    use GridCodec.Struct, template_id: 1, field_defaults: [presence: :required]

    defcodec do
      field :id, :u64
      field :name, :u32
      field :score, :u16
    end
  end

  defmodule RequiredWithOverride do
    use GridCodec.Struct, template_id: 2, field_defaults: [presence: :required]

    defcodec do
      field :id, :u64
      field :name, :u32
      field :description, :string16, presence: :optional
    end
  end

  defmodule DefaultValues do
    use GridCodec.Struct, template_id: 3, field_defaults: [default: 0]

    defcodec do
      field :x, :u32
      field :y, :u32
      field :label, :u32, default: 99
    end
  end

  defmodule EmptyDefaults do
    use GridCodec.Struct, template_id: 4, field_defaults: []

    defcodec do
      field :id, :u64
      field :count, :u32
    end
  end

  defmodule NoDefaults do
    use GridCodec.Struct, template_id: 5

    defcodec do
      field :id, :u64
      field :count, :u32
    end
  end

  # ============================================================================
  # presence: :required via field_defaults
  # ============================================================================

  describe "field_defaults: [presence: :required]" do
    test "all fields become enforce_keys" do
      assert_raise ArgumentError, ~r/the following keys must also be given/, fn ->
        struct!(AllRequired, %{})
      end
    end

    test "struct creation requires all fields" do
      s = %AllRequired{id: 1, name: 2, score: 3}
      assert s.id == 1
      assert s.name == 2
      assert s.score == 3
    end

    test "encode/decode roundtrip" do
      s = %AllRequired{id: 100, name: 200, score: 300}
      {:ok, bin} = AllRequired.encode(s)
      {:ok, decoded} = AllRequired.decode(bin)
      assert decoded.id == 100
      assert decoded.name == 200
      assert decoded.score == 300
    end

    test "encode returns error on nil required field" do
      assert {:error, %GridCodec.ValidationError{}} =
               AllRequired.encode(%AllRequired{id: nil, name: 1, score: 2})
    end

    test "new/1 returns error when required field is nil" do
      assert {:error, %GridCodec.ValidationError{code: :required_field}} =
               AllRequired.new(%{id: nil, name: 1, score: 2})
    end

    test "new/1 returns error when required field is missing" do
      assert {:error, %GridCodec.ValidationError{code: :required_field}} =
               AllRequired.new(%{id: 1, name: 2})
    end

    test "new/1 succeeds when all required fields provided" do
      assert {:ok, %AllRequired{id: 1, name: 2, score: 3}} =
               AllRequired.new(%{id: 1, name: 2, score: 3})
    end
  end

  # ============================================================================
  # Override: explicit field option takes precedence
  # ============================================================================

  describe "explicit field opts override field_defaults" do
    test "overridden field allows nil" do
      s = %RequiredWithOverride{id: 1, name: 2, description: nil}
      {:ok, bin} = RequiredWithOverride.encode(s)
      {:ok, decoded} = RequiredWithOverride.decode(bin)
      assert decoded.description == nil
    end

    test "non-overridden fields are still required" do
      assert {:error, %GridCodec.ValidationError{code: :required_field}} =
               RequiredWithOverride.new(%{description: "hello"})
    end

    test "new/1 succeeds when required fields provided, optional nil" do
      assert {:ok, %RequiredWithOverride{id: 1, name: 2, description: nil}} =
               RequiredWithOverride.new(%{id: 1, name: 2})
    end
  end

  # ============================================================================
  # default: via field_defaults
  # ============================================================================

  describe "field_defaults: [default: 0]" do
    test "fields get default value from field_defaults" do
      s = %DefaultValues{}
      assert s.x == 0
      assert s.y == 0
    end

    test "explicit default overrides field_defaults" do
      s = %DefaultValues{}
      assert s.label == 99
    end

    test "encode/decode with defaults" do
      {:ok, bin} = DefaultValues.encode(%DefaultValues{})
      {:ok, decoded} = DefaultValues.decode(bin)
      assert decoded.x == 0
      assert decoded.y == 0
      assert decoded.label == 99
    end
  end

  # ============================================================================
  # Edge cases
  # ============================================================================

  describe "empty or absent field_defaults" do
    test "empty field_defaults has no effect" do
      s = %EmptyDefaults{}
      assert s.id == nil
      assert s.count == nil
    end

    test "no field_defaults (bare defcodec) still works" do
      s = %NoDefaults{}
      assert s.id == nil
      assert s.count == nil
    end
  end

  # ============================================================================
  # Schema introspection
  # ============================================================================

  describe "__schema__/0 reflects merged options" do
    test "all-required struct has presence: :required in field metadata" do
      schema = AllRequired.__schema__()
      fields = schema.fields

      Enum.each(fields, fn {_name, _type, opts} ->
        assert Keyword.get(opts, :presence) == :required,
               "Expected presence: :required in #{inspect(opts)}"
      end)
    end

    test "overridden field has presence: :optional in schema" do
      schema = RequiredWithOverride.__schema__()
      {_, _, desc_opts} = Enum.find(schema.fields, fn {n, _, _} -> n == :description end)
      assert Keyword.get(desc_opts, :presence) == :optional
    end

    test "non-overridden fields have presence: :required in schema" do
      schema = RequiredWithOverride.__schema__()
      {_, _, id_opts} = Enum.find(schema.fields, fn {n, _, _} -> n == :id end)
      assert Keyword.get(id_opts, :presence) == :required
    end
  end

  # ============================================================================
  # .grid export reflects merged defaults
  # ============================================================================

  describe ".grid export" do
    alias GridCodec.Schema.Formatter

    test "all-required struct emits presence: required on every field in .grid" do
      schema = AllRequired.__schema__()
      output = Formatter.format_struct_file(schema, %{})

      assert output =~ "id: u64, presence: required"
      assert output =~ "name: u32, presence: required"
      assert output =~ "score: u16, presence: required"
    end

    test "overridden field emits no presence (optional is the default)" do
      schema = RequiredWithOverride.__schema__()
      output = Formatter.format_struct_file(schema, %{})

      assert output =~ "id: u64, presence: required"
      assert output =~ "name: u32, presence: required"
      refute output =~ "description: string16, presence: required"
      assert output =~ "description: string16\n"
    end

    test ".grid roundtrip preserves presence from field_defaults" do
      schema = AllRequired.__schema__()
      grid_text = Formatter.format_struct_file(schema, %{})

      {:ok, parsed} = GridCodec.Schema.Parser.parse(grid_text)
      struct_def = parsed.structs |> Map.values() |> hd()

      Enum.each(struct_def.fields, fn field ->
        assert field.presence == :required,
               "Expected presence: :required for #{field.name}, got: #{inspect(field.presence)}"
      end)
    end
  end
end
