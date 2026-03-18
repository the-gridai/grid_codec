defmodule GridCodec.ValidationPipelineTest do
  use ExUnit.Case, async: true

  alias GridCodec.Validations

  defmodule NonNegativeI64 do
    use GridCodec.Type.Refined, base: :i64

    @impl true
    def refine(nil), do: :ok
    def refine(value) when is_integer(value) and value >= 0, do: :ok
    def refine(_value), do: {:error, "must be >= 0"}
  end

  defmodule ValidationCodec do
    use GridCodec.Struct,
      template_id: 9901,
      schema_id: 99,
      version: 1,
      validate: true

    defcodec do
      field :start_ns, NonNegativeI64
      field :end_ns, NonNegativeI64
      field :status, :u8
    end

    validations do
      validate(compare(:end_ns, :>=, :start_ns),
        name: :end_after_start,
        category: :invariant
      )

      validate(one_of(:status, [1, 2]),
        name: :known_status,
        category: :invariant
      )

      validate(&__MODULE__.endpoints_differ/1,
        name: :endpoints_differ,
        category: :invariant
      )

      invariant :status_positive do
        where(status > 0)
      end
    end

    def endpoints_differ(%__MODULE__{start_ns: s, end_ns: e})
        when is_integer(s) and is_integer(e) and s == e do
      [
        GridCodec.ValidationError.invariant_failed(
          __MODULE__,
          :endpoints_differ,
          "start_ns and end_ns must differ"
        )
      ]
    end

    def endpoints_differ(_), do: []
  end

  defmodule RequiredCompareCodec do
    use GridCodec.Struct,
      template_id: 9902,
      schema_id: 99,
      version: 1,
      validate: true,
      field_defaults: [presence: :required]

    defcodec do
      field :a, :u64
      field :b, :u64
      field :status, :u8
    end

    validations do
      validate(compare(:a, :<=, :b), name: :required_compare)
      validate(one_of(:status, [1, 2]), name: :required_one_of)
    end
  end

  defmodule OptionalCompareCodec do
    use GridCodec.Struct,
      template_id: 9903,
      schema_id: 99,
      version: 1,
      validate: true

    defcodec do
      field :a, :u64
      field :b, :u64
    end

    validations do
      validate(compare(:a, :<=, :b), name: :optional_compare)
    end
  end

  defmodule MixedCompareCodec do
    use GridCodec.Struct,
      template_id: 9904,
      schema_id: 99,
      version: 1,
      validate: true

    defcodec do
      field :a, :u64, presence: :required
      field :b, :u64
    end

    validations do
      validate(compare(:a, :<=, :b), name: :mixed_compare)
    end
  end

  defmodule ExplicitOverrideCodec do
    use GridCodec.Struct,
      template_id: 9905,
      schema_id: 99,
      version: 1,
      validate: true,
      field_defaults: [presence: :required]

    defcodec do
      field :a, :u64
      field :b, :u64
      field :status, :u8
      field :optional_status, :u8
    end

    validations do
      validate(compare(:a, :<=, :b, allow_nil?: true), name: :required_compare_override)

      validate(one_of(:optional_status, [1, 2], allow_nil?: false),
        name: :optional_one_of_override
      )
    end
  end

  defmodule ShortCircuitFunctionValidatorCodec do
    use GridCodec.Struct,
      template_id: 9906,
      schema_id: 99,
      version: 1,
      validate: true

    defcodec do
      field :count, :u8
    end

    validations do
      validate(&__MODULE__.count_must_be_even/1,
        name: :count_must_be_even,
        category: :invariant
      )
    end

    def count_must_be_even(%__MODULE__{count: count}) do
      if rem(count, 2) == 0 do
        []
      else
        [
          GridCodec.ValidationError.invariant_failed(
            __MODULE__,
            :count_must_be_even,
            "count must be even"
          )
        ]
      end
    end
  end

  defp debug_info(module, binary) do
    {:ok, {^module, [debug_info: {:debug_info_v1, :elixir_erl, {:elixir_v1, data, _}}]}} =
      :beam_lib.chunks(binary, [:debug_info])

    data
  end

  defp function_forms(module, binary, name, arity) do
    module
    |> debug_info(binary)
    |> Map.fetch!(:definitions)
    |> Enum.filter(fn
      {{^name, ^arity}, _kind, _meta, _clauses} -> true
      _ -> false
    end)
  end

  defp compile_fixture!(source, label) do
    previous = Code.compiler_options()
    Code.compiler_options(debug_info: true)

    try do
      [{module, binary}] = Code.compile_string(source, label)
      {module, binary}
    after
      Code.compiler_options(previous)
    end
  end

  defp contains_is_nil?(term) when is_tuple(term) do
    term
    |> Tuple.to_list()
    |> Enum.any?(&contains_is_nil?/1)
  end

  defp contains_is_nil?(term) when is_list(term), do: Enum.any?(term, &contains_is_nil?/1)
  defp contains_is_nil?(nil), do: true
  defp contains_is_nil?(:is_nil), do: true
  defp contains_is_nil?(_term), do: false

  defp framed_binary(payload) do
    {:ok, valid} = ValidationCodec.encode(%ValidationCodec{start_ns: 1, end_ns: 2, status: 1})
    <<header::binary-size(8), _::binary>> = valid
    <<header::binary, payload::binary>>
  end

  describe "type-level refined validations" do
    test "new/1 returns a cast error for refined type coercion failures" do
      assert {:error, %GridCodec.ValidationError{code: :cast_error} = error} =
               ValidationCodec.new(start_ns: -1, end_ns: 2, status: 1)

      assert error.details.field == :start_ns
      assert error.details.value == -1
      assert error.details.description =~ "must be >= 0"
    end

    test "encode/1 returns invariant_failed for invalid refined values on structs" do
      struct = %ValidationCodec{start_ns: -1, end_ns: 2, status: 1}

      assert {:error, %GridCodec.ValidationError{code: :invariant_failed} = error} =
               ValidationCodec.encode(struct)

      assert error.details.name == :start_ns
      assert error.details.description =~ "must be >= 0"
      assert error.details.metadata.validation == :type_refinement
    end

    test "type validation short-circuits function validators" do
      struct = %ShortCircuitFunctionValidatorCodec{count: "not-an-integer"}

      assert {:error, %GridCodec.ValidationError{code: :out_of_range} = error} =
               ShortCircuitFunctionValidatorCodec.validate_struct(struct)

      assert error.details.field == :count
    end
  end

  describe "decoded validation pipeline" do
    test "GridCodec.Validations builtins return normalized descriptors" do
      assert %{kind: :compare, supports: [:decoded, :binary]} =
               Validations.compare(:end_ns, :>=, :start_ns)

      assert %{kind: :present, field: :status} = Validations.present(:status)
      assert %{kind: :one_of, allowed: [1, 2]} = Validations.one_of(:status, [1, 2])
    end

    test "accumulates multiple invariant failures on structs" do
      struct = %ValidationCodec{start_ns: 5, end_ns: 3, status: 9}

      assert {:error, %GridCodec.ValidationErrors{errors: errors}} =
               ValidationCodec.validate_struct(struct)

      assert Enum.map(errors, & &1.details.name) == [:end_after_start, :known_status]
    end

    test "supports function validators in the pipeline" do
      struct = %ValidationCodec{start_ns: 5, end_ns: 5, status: 1}

      assert {:error, %GridCodec.ValidationError{} = error} =
               ValidationCodec.validate_struct(struct)

      assert error.details.name == :endpoints_differ
    end

    test "__validations__/0 exposes metadata for builtins and callbacks" do
      validations = ValidationCodec.__validations__()

      assert Enum.find(validations, &(&1.name == :end_after_start)).supports == [
               :decoded,
               :binary
             ]

      assert Enum.find(validations, &(&1.name == :endpoints_differ)).supports == [:decoded]
      assert Enum.find(validations, &(&1.name == :status_positive)).kind == :compare
    end

    test "required-field builtins infer allow_nil?: false in metadata" do
      validations = RequiredCompareCodec.__validations__()

      assert Enum.find(validations, &(&1.name == :required_compare)).allow_nil? == false
      assert Enum.find(validations, &(&1.name == :required_one_of)).allow_nil? == false
    end

    test "optional-field compare keeps allow_nil?: true by default" do
      validations = OptionalCompareCodec.__validations__()

      assert Enum.find(validations, &(&1.name == :optional_compare)).allow_nil? == true
    end

    test "mixed required and optional compare stays nil-aware by default" do
      validations = MixedCompareCodec.__validations__()

      assert Enum.find(validations, &(&1.name == :mixed_compare)).allow_nil? == true
    end

    test "explicit allow_nil? override wins over inferred defaults" do
      validations = ExplicitOverrideCodec.__validations__()

      assert Enum.find(validations, &(&1.name == :required_compare_override)).allow_nil? == true

      assert Enum.find(validations, &(&1.name == :optional_one_of_override)).allow_nil? ==
               false
    end

    test "required-only compare codegen omits nil checks" do
      unique = System.unique_integer([:positive])

      required_source = """
      defmodule ValidationShapeRequired#{unique} do
        use GridCodec.Struct,
          template_id: 19901,
          schema_id: 99,
          version: 1,
          validate: true,
          field_defaults: [presence: :required]

        defcodec do
          field :a, :u64
          field :b, :u64
        end

        validations do
          validate(compare(:a, :<=, :b), name: :required_compare)
        end
      end
      """

      optional_source = """
      defmodule ValidationShapeOptional#{unique} do
        use GridCodec.Struct,
          template_id: 19902,
          schema_id: 99,
          version: 1,
          validate: true

        defcodec do
          field :a, :u64
          field :b, :u64
        end

        validations do
          validate(compare(:a, :<=, :b), name: :optional_compare)
        end
      end
      """

      {required_module, required_binary} =
        compile_fixture!(required_source, "validation_shape_required_#{unique}.ex")

      {optional_module, optional_binary} =
        compile_fixture!(optional_source, "validation_shape_optional_#{unique}.ex")

      refute contains_is_nil?(
               function_forms(
                 required_module,
                 required_binary,
                 :__collect_validator_errors__,
                 1
               )
             )

      assert contains_is_nil?(
               function_forms(
                 optional_module,
                 optional_binary,
                 :__collect_validator_errors__,
                 1
               )
             )
    end
  end

  describe "binary validation" do
    test "validates framed binaries with binary-capable validators" do
      payload = <<5::little-signed-64, 3::little-signed-64, 9::8>>
      binary = framed_binary(payload)

      assert {:error, %GridCodec.ValidationErrors{errors: errors}} =
               ValidationCodec.validate_binary(binary)

      assert Enum.map(errors, & &1.details.name) == [:end_after_start, :known_status]
    end

    test "validates payload-only binaries when header is false" do
      payload = <<5::little-signed-64, 3::little-signed-64, 9::8>>

      assert {:error, %GridCodec.ValidationErrors{errors: errors}} =
               ValidationCodec.validate_binary(payload, header: false)

      assert Enum.map(errors, & &1.details.name) == [:end_after_start, :known_status]
    end

    test "valid?/2 works for structs and binaries" do
      assert ValidationCodec.valid?(%ValidationCodec{start_ns: 1, end_ns: 2, status: 1})
      refute ValidationCodec.valid?(%ValidationCodec{start_ns: 5, end_ns: 3, status: 9})

      assert ValidationCodec.valid?(
               framed_binary(<<1::little-signed-64, 2::little-signed-64, 1::8>>)
             )

      refute ValidationCodec.valid?(
               framed_binary(<<5::little-signed-64, 3::little-signed-64, 9::8>>)
             )
    end
  end

  describe "decode validation modes" do
    test "decode(validate: :binary) rejects invalid framed binaries" do
      binary = framed_binary(<<5::little-signed-64, 3::little-signed-64, 9::8>>)

      assert {:error, %GridCodec.ValidationErrors{errors: errors}} =
               ValidationCodec.decode(binary, validate: :binary)

      assert Enum.map(errors, & &1.details.name) == [:end_after_start, :known_status]
    end

    test "decode(validate: :decoded) can run decoded-only validators" do
      binary = framed_binary(<<5::little-signed-64, 5::little-signed-64, 1::8>>)

      assert {:error, %GridCodec.ValidationError{} = error} =
               ValidationCodec.decode(binary, validate: :decoded)

      assert error.details.name == :endpoints_differ
    end

    test "decode(validate: :both) combines binary and decoded checks" do
      binary = framed_binary(<<5::little-signed-64, 5::little-signed-64, 9::8>>)

      assert {:error, %GridCodec.ValidationErrors{errors: errors}} =
               ValidationCodec.decode(binary, validate: :both)

      assert Enum.map(errors, & &1.details.name) == [:known_status, :endpoints_differ]
    end
  end
end
