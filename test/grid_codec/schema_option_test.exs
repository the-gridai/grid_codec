Application.put_env(:grid_codec, :grid_codec,
  schemas: %{950 => "test_exchange", 951 => "test_other"}
)

defmodule GridCodec.SchemaOptionTest do
  use ExUnit.Case, async: true

  describe "schema: named option" do
    defmodule ResolvedSchema do
      use GridCodec.Struct, template_id: 950, schema: "test_exchange"

      defcodec do
        field :id, :u64
      end
    end

    test "resolves schema name to numeric ID" do
      assert ResolvedSchema.__schema_id__() == 950
    end

    test "__schema__/0 contains the resolved schema_id" do
      assert ResolvedSchema.__schema__().schema_id == 950
    end

    defmodule ResolvedOther do
      use GridCodec.Struct, template_id: 951, schema: "test_other"

      defcodec do
        field :value, :u32
      end
    end

    test "resolves a different schema name" do
      assert ResolvedOther.__schema_id__() == 951
    end

    test "encode/decode roundtrip works with resolved schema" do
      struct = %ResolvedSchema{id: 42}
      assert {:ok, bin} = ResolvedSchema.encode(struct)
      assert {:ok, ^struct} = ResolvedSchema.decode(bin)
    end
  end

  describe "schema_id: backward compatibility" do
    defmodule ExplicitSchemaId do
      use GridCodec.Struct, template_id: 952, schema_id: 123

      defcodec do
        field :id, :u64
      end
    end

    test "schema_id: still works as-is" do
      assert ExplicitSchemaId.__schema_id__() == 123
    end
  end

  describe "schema: compile-time errors" do
    test "raises when schema: and schema_id: are both provided" do
      assert_raise ArgumentError, ~r/mutually exclusive/, fn ->
        defmodule ConflictingSchema do
          use GridCodec.Struct, template_id: 960, schema: "test_exchange", schema_id: 100

          defcodec do
            field :id, :u64
          end
        end
      end
    end

    test "raises for unknown schema name" do
      assert_raise ArgumentError, ~r/Unknown schema "nonexistent"/, fn ->
        defmodule UnknownSchema do
          use GridCodec.Struct, template_id: 961, schema: "nonexistent"

          defcodec do
            field :id, :u64
          end
        end
      end
    end

    test "error message lists available schemas" do
      err =
        assert_raise ArgumentError, fn ->
          defmodule UnknownSchema2 do
            use GridCodec.Struct, template_id: 962, schema: "missing"

            defcodec do
              field :id, :u64
            end
          end
        end

      assert err.message =~ "test_exchange"
      assert err.message =~ "test_other"
    end

    test "raises when schema: is not a string" do
      assert_raise ArgumentError, ~r/schema: must be a string/, fn ->
        defmodule BadSchemaType do
          use GridCodec.Struct, template_id: 963, schema: :not_a_string

          defcodec do
            field :id, :u64
          end
        end
      end
    end
  end
end
