alias Ecto.Adapters.SQL
alias ExampleApp.Repo
alias GridCodec.SQL, as: GridCodecSQL

Application.ensure_all_started(:example_app)
Logger.configure(level: :warning)

suffix = System.unique_integer([:positive])

compile_codec! = fn version ->
  module = Module.concat(ExampleApp.Events, "SQLMigrationEventV#{version}_#{suffix}")

  fields =
    case version do
      1 ->
        quote do
          field :event_id, :u64
          field :label, :string16
        end

      2 ->
        quote do
          field :event_id, :u64
          field :score, :u32, since: 2
          field :label, :string16
        end

      3 ->
        quote do
          field :event_id, :u64
          field :score, :u32, since: 2
          field :risk_tier, :u16, since: 3
          field :label, :string16
        end
    end

  Code.compile_quoted(
    quote do
      defmodule unquote(module) do
        use GridCodec.Struct,
          template_id: 990,
          schema_id: 990,
          version: unquote(version),
          name: "ExampleApp.Events.SQLMigrationEvent"

        defcodec do
          unquote(fields)
        end
      end
    end
  )

  module
end

unload_codec! = fn module ->
  :code.purge(module)
  :code.delete(module)
end

table = "gridcodec_sql_evolution_events"
typed_stream_function = "public.gridcodec_sql_evolution_typed_stream"

execute_catalog! = fn module ->
  statements =
    GridCodecSQL.drop_statements([module]) ++
      GridCodecSQL.generate_all_statements([module])

  Enum.each(statements, &SQL.query!(Repo, &1, []))
end

refresh_typed_stream! = fn module ->
  opts = [
    function: typed_stream_function,
    table: "public.#{table}",
    decode: {:typed, module}
  ]

  SQL.query!(Repo, GridCodecSQL.drop_stream_decoder_statement(opts), [])
  SQL.query!(Repo, GridCodecSQL.generate_stream_decoder(opts), [])
end

append_event! = fn version, event ->
  {:ok, data} = event.__struct__.encode(event)

  SQL.query!(
    Repo,
    """
    INSERT INTO #{table} (stream_id, stream_version, event_type, data)
    VALUES ('account-1', $1, $2, $3)
    """,
    [version, event.__struct__.__type__(), data]
  )
end

assert_rows! = fn query, expected ->
  %{rows: rows} = SQL.query!(Repo, query, [])

  if rows != expected do
    raise """
    unexpected SQL evolution rows
    expected: #{inspect(expected)}
    actual:   #{inspect(rows)}
    """
  end
end

SQL.query!(Repo, "DROP TABLE IF EXISTS #{table}", [])

SQL.query!(
  Repo,
  """
  CREATE UNLOGGED TABLE #{table} (
    stream_id text NOT NULL,
    stream_version bigint NOT NULL,
    event_type text NOT NULL,
    data bytea NOT NULL,
    PRIMARY KEY (stream_id, stream_version)
  )
  """,
  []
)

try do
  v1 = compile_codec!.(1)
  append_event!.(1, struct(v1, event_id: 101, label: "v1"))
  execute_catalog!.(v1)
  refresh_typed_stream!.(v1)

  assert_rows!.(
    """
    SELECT stream_version, event_id::bigint, label
    FROM #{typed_stream_function}('account-1')
    """,
    [[1, 101, "v1"]]
  )

  unload_codec!.(v1)
  v2 = compile_codec!.(2)
  append_event!.(2, struct(v2, event_id: 102, score: 22, label: "v2"))
  execute_catalog!.(v2)
  refresh_typed_stream!.(v2)

  assert_rows!.(
    """
    SELECT stream_version, event_id::bigint, score, label
    FROM #{typed_stream_function}('account-1')
    """,
    [[1, 101, nil, "v1"], [2, 102, 22, "v2"]]
  )

  assert_rows!.(
    """
    SELECT
      stream_version,
      gridcodec.read_exampleapp_events_sqlmigrationevent_score(data)
    FROM #{table}
    ORDER BY stream_version
    """,
    [[1, nil], [2, 22]]
  )

  unload_codec!.(v2)
  v3 = compile_codec!.(3)
  append_event!.(3, struct(v3, event_id: 103, score: 33, risk_tier: 3, label: "v3"))
  execute_catalog!.(v3)
  refresh_typed_stream!.(v3)
  execute_catalog!.(v3)
  refresh_typed_stream!.(v3)

  assert_rows!.(
    """
    SELECT
      stream_version,
      event_id::bigint,
      score,
      risk_tier,
      label
    FROM #{typed_stream_function}('account-1')
    """,
    [[1, 101, nil, nil, "v1"], [2, 102, 22, nil, "v2"], [3, 103, 33, 3, "v3"]]
  )

  assert_rows!.(
    """
    SELECT
      stream_version,
      gridcodec.decode(event_type, data)
    FROM #{table}
    ORDER BY stream_version
    """,
    [
      [
        1,
        %{
          "event_id" => 101,
          "label" => "v1",
          "risk_tier" => nil,
          "score" => nil
        }
      ],
      [
        2,
        %{
          "event_id" => 102,
          "label" => "v2",
          "risk_tier" => nil,
          "score" => 22
        }
      ],
      [
        3,
        %{
          "event_id" => 103,
          "label" => "v3",
          "risk_tier" => 3,
          "score" => 33
        }
      ]
    ]
  )

  IO.puts("GridCodec SQL decoder evolution test passed: V1 -> V2 -> V3 -> V3 rerun")
  unload_codec!.(v3)
after
  SQL.query!(
    Repo,
    GridCodecSQL.drop_stream_decoder_statement(function: typed_stream_function),
    []
  )

  SQL.query!(Repo, "DROP TABLE IF EXISTS #{table}", [])
end
