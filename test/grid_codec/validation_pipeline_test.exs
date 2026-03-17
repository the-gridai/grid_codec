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
