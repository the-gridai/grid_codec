defmodule GridCodec.SQLGrowthTest do
  use ExUnit.Case, async: false

  alias GridCodec.SQL

  test "typed, JSON, and native-stream SQL grow linearly with variable fields" do
    small = compile_codec(8)
    large = compile_codec(16)

    # Check 16 before generating larger schemas: the old generator doubles the
    # previous expression at each field and cannot safely generate 32 fields.
    assert byte_size(SQL.generate(large)) < 40_000
    assert byte_size(SQL.generate(large)) < 3 * byte_size(SQL.generate(small))

    assert byte_size(SQL.generate_all([large])) < 3 * byte_size(SQL.generate_all([small]))

    stream = fn module ->
      SQL.generate_stream_decoder(
        function: "public.read_growth_stream",
        table: "public.events",
        decode: {:typed, module}
      )
    end

    assert byte_size(stream.(large)) < 3 * byte_size(stream.(small))
    assert byte_size(SQL.generate(compile_codec(32))) < 80_000
  end

  test "single-event decoders advertise one output row" do
    sql = SQL.generate(GridCodec.TestSupport.OrderEvent)
    assert sql =~ "ROWS 1"
  end

  test "JSON objects wider than 50 fields are split below the PostgreSQL argument limit" do
    sql = SQL.generate_all([compile_codec(64, :u32)])
    assert sql =~ " || jsonb_build_object("
  end

  defp compile_codec(count, type \\ :string16) do
    module = Module.concat(__MODULE__, "Fields#{count}_#{type}")

    fields =
      for index <- 1..count do
        name = String.to_atom("field_#{index}")

        quote do
          field unquote(name), unquote(type)
        end
      end

    Code.compile_quoted(
      quote do
        defmodule unquote(module) do
          use GridCodec.Struct,
            template_id: unquote(700 + count),
            schema_id: 63,
            name: unquote("SQLGrowth#{count}_#{type}")

          defcodec do
            (unquote_splicing(fields))
          end
        end
      end
    )

    module
  end
end
