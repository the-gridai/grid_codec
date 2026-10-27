# Run against a disposable example database:
# DATABASE_HOST=localhost DATABASE_PORT=5432 mix run priv/sql_offset_regression_test.exs
defmodule SQLOffsetRegression do
  @moduledoc false

  alias ExampleApp.Repo
  alias GridCodec.SQL

  def run do
    Logger.configure(level: :warning)
    old = codec(:Old, 10, 1)
    old_data = encode!(old, 10)
    :code.purge(old)
    :code.delete(old)
    current = codec(:Current, 16, 3)
    wide = codec(:Wide, 64, 1, :u32)
    install!([current, wide])

    try do
      verify_history!(old_data, current)
      verify_wide_json!(wide)
      verify_offsets!()
      verify_stream!(current)

      IO.puts(
        "SQL offset regressions passed: historical tails, empty/UTF-8 strings, wide JSON, cursor, native streams."
      )
    after
      Repo.query!(
        "DROP FUNCTION IF EXISTS public.sql_offset_regression_stream(text, bigint, integer)"
      )

      Repo.query!("DROP TABLE IF EXISTS sql_offset_regression_events")
      Enum.each(SQL.drop_statements([current, wide]), &Repo.query!/1)
    end
  end

  defp codec(suffix, count, version, type \\ :string16) do
    module = Module.concat(__MODULE__, suffix)

    fields =
      for index <- 1..count do
        name = String.to_atom("field_#{index}")
        since = if type == :string16 and index > 10, do: if(index > 13, do: 3, else: 2), else: 1

        quote do
          field unquote(name), unquote(type), since: unquote(since), presence: :optional
        end
      end

    Code.compile_quoted(
      quote do
        defmodule unquote(module) do
          use GridCodec.Struct,
            template_id: unquote(if(type == :u32, do: 992, else: 991)),
            schema_id: 991,
            version: unquote(version),
            name: unquote(if(type == :u32, do: "SQLWideObject", else: "SQLVariableTail"))

          defcodec do
            (unquote_splicing(fields))
          end
        end
      end
    )

    module
  end

  defp install!(modules) do
    Enum.each(
      SQL.drop_statements(modules) ++ SQL.generate_all_statements(modules),
      &Repo.query!/1
    )
  end

  defp verify_history!(old_data, current) do
    for {data, count} <- [{old_data, 10}, {encode!(current, 16), 16}] do
      %{rows: [[typed, json]]} =
        Repo.query!(
          "SELECT to_jsonb(d), gridcodec.decode_sqlvariabletail_json($1) FROM gridcodec.decode_sqlvariabletail($1) d",
          [data]
        )

      expected = Map.new(1..16, &{"field_#{&1}", if(&1 <= count, do: string_value(&1))})
      assert!(typed == expected and json == expected, "historical typed/JSON mismatch")
    end

    %{rows: [[0, nil]]} =
      Repo.query!(
        "SELECT count(*), gridcodec.decode_sqlvariabletail_json(NULL) FROM gridcodec.decode_sqlvariabletail(NULL)"
      )
  end

  defp verify_wide_json!(module) do
    event = struct(module, Map.new(1..64, &{String.to_atom("field_#{&1}"), &1}))
    {:ok, data} = module.encode(event)
    %{rows: [[json]]} = Repo.query!("SELECT gridcodec.decode_sqlwideobject_json($1)", [data])
    assert!(json == Map.new(1..64, &{"field_#{&1}", &1}), "wide JSON object mismatch")
  end

  defp verify_offsets! do
    # Two groups: (block length 3, count 2), then an empty group. Two strings.
    data =
      <<0::little-16, 991::little-16, 991::little-16, 1::little-16, 3::little-16, 2::little-16,
        0::48, 5::little-16, 0::little-16, 3::little-16, "abc", 0::little-16>>

    %{rows: [[positions]]} =
      Repo.query!("SELECT gridcodec.field_offsets($1, 2, ARRAY[0,0])", [data])

    assert!(positions == [8, 18, 22, 27], "group/variable cursor mismatch")
  end

  defp verify_stream!(module) do
    Repo.query!(
      "CREATE TABLE sql_offset_regression_events (stream_id text, stream_version bigint, event_type text, data bytea)"
    )

    Repo.query!("CREATE INDEX ON sql_offset_regression_events (stream_id, stream_version)")

    Repo.query!(
      "INSERT INTO sql_offset_regression_events VALUES ('one', 1, 'SQLVariableTail', $1)",
      [encode!(module, 16)]
    )

    Repo.query!(
      SQL.generate_stream_decoder(
        function: "public.sql_offset_regression_stream",
        table: "public.sql_offset_regression_events",
        decode: {:typed, module}
      )
    )

    %{rows: [row]} = Repo.query!("SELECT * FROM sql_offset_regression_stream('one', 1, 1)")
    assert!(Enum.drop(row, 2) == Enum.map(1..16, &string_value/1), "native stream mismatch")
  end

  defp encode!(module, count) do
    values = Map.new(1..count, &{String.to_atom("field_#{&1}"), string_value(&1) || ""})
    {:ok, data} = module.encode(struct(module, values))
    data
  end

  defp string_value(2), do: nil
  defp string_value(index), do: "東京-#{index}"

  defp assert!(true, _message), do: :ok
  defp assert!(false, message), do: raise(message)
end

SQLOffsetRegression.run()
