# PostgreSQL decoder and indexed stream-query benchmark
#
# Run from example_app/:
#   DATABASE_HOST=db MIX_ENV=prod mix run benchmarks/sql_decode_bench.exs
#   GRIDCODEC_SQL_SKIP_LATENCY=1 DATABASE_HOST=db MIX_ENV=prod \
#     mix run benchmarks/sql_decode_bench.exs
#
# Cached PostgreSQL execution time is a CPU-dominant proxy, not a direct
# process-CPU counter. Retained backend memory and plan-node peak memory are
# reported separately from the decoded result size.

defmodule SQLDecodeBench do
  @moduledoc false

  alias ExampleApp.Events.OrderCreated
  alias ExampleApp.Events.TradeExecuted
  alias ExampleApp.Repo
  alias ExampleApp.Views.CurrencyAccount
  alias ExampleApp.Views.Reservation
  alias GridCodec.SQL

  @table "gridcodec_sql_bench_events"
  @stream_function "gridcodec_sql_bench_decode_stream"
  @raw_stream_function "gridcodec_sql_bench_read_stream"
  @projected_stream_function "gridcodec_sql_bench_project_stream"
  @typed_stream_function "gridcodec_sql_bench_typed_stream"
  @scalar_rows System.get_env("GRIDCODEC_SQL_SCALAR_ROWS", "100000") |> String.to_integer()

  def run do
    Logger.configure(level: :warning)
    setup!()

    try do
      print_database_report()
      print_fast_path_report()

      unless System.get_env("GRIDCODEC_SQL_SKIP_LATENCY") == "1" do
        run_latency_benchmarks()
      end
    after
      cleanup!()
    end
  end

  defp setup! do
    drop_stream_functions!()
    Repo.query!("DROP TABLE IF EXISTS #{@table}")

    Repo.query!("""
    CREATE UNLOGGED TABLE #{@table} (
      stream_id text NOT NULL,
      stream_version bigint NOT NULL,
      event_type text NOT NULL,
      data bytea NOT NULL,
      PRIMARY KEY (stream_id, stream_version)
    )
    """)

    install_decoders!()

    fixed_binary = encode_fixed_event!()
    grouped_binary = encode_grouped_event!()

    for size <- [1, 10, 100, 1_000] do
      insert_fixed_stream!("fixed-#{size}", size, OrderCreated.__type__(), fixed_binary)
    end

    insert_fixed_stream!(
      "scalar-#{@scalar_rows}",
      @scalar_rows,
      OrderCreated.__type__(),
      fixed_binary
    )

    insert_stream!("grouped-100", 100, CurrencyAccount.__type__(), grouped_binary)
    Repo.query!("ANALYZE #{@table}")
  end

  defp install_decoders! do
    sql =
      SQL.generate_all([OrderCreated, TradeExecuted, CurrencyAccount]) <>
        SQL.generate_stream_decoder(
          function: "public.#{@stream_function}",
          table: "public.#{@table}",
          stream_id_type: :text
        ) <>
        SQL.generate_stream_decoder(
          function: "public.#{@raw_stream_function}",
          table: "public.#{@table}",
          stream_id_type: :text,
          decode: :raw
        ) <>
        SQL.generate_stream_decoder(
          function: "public.#{@projected_stream_function}",
          table: "public.#{@table}",
          stream_id_type: :text,
          decode: {:fields, OrderCreated, [:side, :price, :quantity]}
        ) <>
        SQL.generate_stream_decoder(
          function: "public.#{@typed_stream_function}",
          table: "public.#{@table}",
          stream_id_type: :text,
          decode: {:typed, OrderCreated}
        )

    path = Path.join(System.tmp_dir!(), "gridcodec_sql_benchmark.sql")
    File.write!(path, sql)

    config = Repo.config()

    {output, exit_code} =
      System.cmd(
        "psql",
        [
          "-h",
          Keyword.get(config, :hostname, "localhost"),
          "-p",
          to_string(Keyword.get(config, :port, 5432)),
          "-U",
          Keyword.get(config, :username, "postgres"),
          "-d",
          Keyword.fetch!(config, :database),
          "-v",
          "ON_ERROR_STOP=1",
          "-f",
          path
        ],
        env: [{"PGPASSWORD", Keyword.get(config, :password, "postgres")}],
        stderr_to_stdout: true
      )

    File.rm!(path)

    if exit_code != 0 do
      raise "failed to install generated SQL:\n#{output}"
    end
  end

  defp encode_fixed_event! do
    event = %OrderCreated{
      order_id: <<1::128>>,
      user_id: 42,
      symbol: "BTC/USD",
      side: :buy,
      price: 67_500,
      quantity: 100,
      timestamp: 1_709_000_000_000_000,
      flags: 1
    }

    {:ok, binary} = OrderCreated.encode(event)
    binary
  end

  defp encode_grouped_event! do
    event = %CurrencyAccount{
      account_id: 7,
      reservations: [
        %Reservation{
          reservation_id: 701,
          order_id: 42,
          amount: 15_000,
          active: true,
          expires_at: ~U[2026-07-26 12:00:00.000000Z]
        },
        %Reservation{
          reservation_id: 702,
          order_id: 43,
          amount: 5_000,
          active: false,
          expires_at: nil
        }
      ]
    }

    {:ok, binary} = CurrencyAccount.encode(event)
    binary
  end

  defp insert_stream!(stream_id, count, event_type, binary) do
    Repo.query!(
      """
      INSERT INTO #{@table} (stream_id, stream_version, event_type, data)
      SELECT $1, version, $2, $3
      FROM generate_series(1, $4) AS version
      """,
      [stream_id, event_type, binary, count]
    )
  end

  defp insert_fixed_stream!(stream_id, count, event_type, binary) do
    Repo.query!(
      """
      INSERT INTO #{@table} (stream_id, stream_version, event_type, data)
      SELECT
        $1,
        version,
        $2,
        set_byte(
          set_byte($3, 24, (version % 254)::integer),
          25,
          ((version / 254) % 254)::integer
        )
      FROM generate_series(1, $4) AS version
      """,
      [stream_id, event_type, binary, count]
    )
  end

  defp print_database_report do
    IO.puts("""
    GridCodec PostgreSQL decoder benchmark

    DB execution time is measured by EXPLAIN ANALYZE after a warm-up and is a
    CPU-dominant proxy with cached data. Memory reports decoded JSON size,
    retained backend-memory delta, plan-node peak memory, and temp-buffer spill.
    """)

    for stream_id <- ["fixed-1", "fixed-10", "fixed-100", "fixed-1000", "grouped-100"] do
      report = measure_database(stream_id)

      IO.puts("""
      #{stream_id}
        events: #{report.events}
        execution: #{Float.round(report.execution_ms, 3)} ms
        decoded JSON: #{format_bytes(report.decoded_bytes)}
        retained backend delta: #{format_signed_bytes(report.retained_bytes)}
        max plan-node memory: #{report.peak_plan_memory_kb} kB
        buffers: hit=#{report.shared_hit_blocks}, read=#{report.shared_read_blocks}, temp_read=#{report.temp_read_blocks}, temp_written=#{report.temp_written_blocks}
        plan nodes: #{Enum.join(report.plan_nodes, ", ")}
      """)
    end
  end

  defp print_fast_path_report do
    scalar_stream = "scalar-#{@scalar_rows}"

    reports =
      [
        {
          "scalar fixed-field aggregate / #{@scalar_rows} events",
          @scalar_rows,
          """
          SELECT count(*)::bigint,
                 sum(gridcodec.read_ordercreated_quantity(data))
          FROM #{@table}
          WHERE stream_id = $1
          """,
          [scalar_stream]
        },
        {
          "raw indexed stream / 1000 events",
          1_000,
          """
          SELECT count(*)::bigint, sum(octet_length(data))::bigint
          FROM public.#{@raw_stream_function}($1)
          """,
          ["fixed-1000"]
        },
        {
          "selected native columns / 1000 events",
          1_000,
          """
          SELECT count(*)::bigint, sum(quantity), sum(price)
          FROM public.#{@projected_stream_function}($1)
          """,
          ["fixed-1000"]
        },
        {
          "native UUID column / 1000 events",
          1_000,
          """
          SELECT count(*)::bigint,
                 sum(pg_column_size(gridcodec.read_ordercreated_order_id(data)))::bigint
          FROM #{@table}
          WHERE stream_id = $1
          """,
          ["fixed-1000"]
        },
        {
          "native string column / 1000 events",
          1_000,
          """
          SELECT count(*)::bigint,
                 sum(pg_column_size(gridcodec.read_string16(
                   data,
                   8 + gridcodec.read_u16(data, 0)
                 )))::bigint
          FROM #{@table}
          WHERE stream_id = $1
          """,
          ["fixed-1000"]
        },
        {
          "native timestamp column / 1000 events",
          1_000,
          """
          SELECT count(*)::bigint,
                 sum(pg_column_size(gridcodec.read_ordercreated_timestamp(data)))::bigint
          FROM #{@table}
          WHERE stream_id = $1
          """,
          ["fixed-1000"]
        },
        {
          "set-based native typed rows / 1000 events",
          1_000,
          """
          SELECT count(*)::bigint,
                 sum(pg_column_size(ROW(
                   order_id,
                   user_id,
                   symbol,
                   side,
                   price,
                   quantity,
                   timestamp,
                   flags
                 )))::bigint
          FROM public.#{@typed_stream_function}($1)
          """,
          ["fixed-1000"]
        },
        {
          "typed full row / 1000 events",
          1_000,
          """
          SELECT count(*)::bigint, sum(pg_column_size(decoded))::bigint
          FROM (
            SELECT decoded
            FROM #{@table} AS events
            CROSS JOIN LATERAL gridcodec.decode_ordercreated(events.data) AS decoded
            WHERE events.stream_id = $1
          ) AS rows
          """,
          ["fixed-1000"]
        }
      ] ++ plrust_reports(scalar_stream)

    IO.puts("Fast-path comparison (values fully consumed):\n")

    for {label, event_count, query, params} <- reports do
      report = measure_query(query, params)
      events_per_second = event_count / (report.execution_ms / 1_000)

      IO.puts("""
      #{label}
        execution: #{Float.round(report.execution_ms, 3)} ms
        throughput: #{round(events_per_second)} events/s
        buffers: hit=#{report.shared_hit_blocks}, read=#{report.shared_read_blocks}, temp_read=#{report.temp_read_blocks}, temp_written=#{report.temp_written_blocks}
        plan nodes: #{Enum.join(report.plan_nodes, ", ")}
      """)
    end
  end

  defp plrust_reports(stream_id) do
    %{rows: [[available?]]} =
      Repo.query!(
        "SELECT to_regprocedure('gridcodec_plrust.read_u32(bytea,integer)') IS NOT NULL"
      )

    if available? do
      {_type_mod, quantity_offset, _endian} =
        OrderCreated.__field_specs__() |> Map.fetch!(:quantity)

      [
        {
          "optional PL/Rust scalar aggregate / #{@scalar_rows} events",
          @scalar_rows,
          """
          SELECT count(*)::bigint,
                 sum(NULLIF(gridcodec_plrust.read_u32(data, #{quantity_offset}), 4294967295))
          FROM #{@table}
          WHERE stream_id = $1
          """,
          [stream_id]
        }
      ]
    else
      IO.puts("Optional PL/Rust reader not installed; native comparison skipped.\n")
      []
    end
  end

  defp measure_query(query, params) do
    Repo.checkout(fn ->
      Repo.query!(query, params)

      %{rows: [[[explain]]]} =
        Repo.query!("EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) #{query}", params)

      plan = explain["Plan"]

      %{
        execution_ms: explain["Execution Time"],
        plan_nodes: plan_node_types(plan),
        shared_hit_blocks: sum_plan_value(plan, "Shared Hit Blocks"),
        shared_read_blocks: sum_plan_value(plan, "Shared Read Blocks"),
        temp_read_blocks: sum_plan_value(plan, "Temp Read Blocks"),
        temp_written_blocks: sum_plan_value(plan, "Temp Written Blocks")
      }
    end)
  end

  defp measure_database(stream_id) do
    Repo.checkout(fn ->
      aggregate_stream!(stream_id)
      baseline_memory = backend_memory_bytes!()
      explain = explain_stream!(stream_id)
      [events, decoded_bytes] = aggregate_stream!(stream_id)
      retained_memory = backend_memory_bytes!() - baseline_memory
      plan = explain["Plan"]

      %{
        events: events,
        decoded_bytes: decoded_bytes,
        execution_ms: explain["Execution Time"],
        retained_bytes: retained_memory,
        peak_plan_memory_kb:
          max(
            max_plan_value(plan, "Peak Memory Usage"),
            max_plan_value(plan, "Sort Space Used")
          ),
        plan_nodes: plan_node_types(plan),
        shared_hit_blocks: sum_plan_value(plan, "Shared Hit Blocks"),
        shared_read_blocks: sum_plan_value(plan, "Shared Read Blocks"),
        temp_read_blocks: sum_plan_value(plan, "Temp Read Blocks"),
        temp_written_blocks: sum_plan_value(plan, "Temp Written Blocks")
      }
    end)
  end

  defp explain_stream!(stream_id) do
    %{rows: [[[explain]]]} =
      Repo.query!(
        """
        EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
        SELECT count(*)::bigint, COALESCE(sum(pg_column_size(decoded)), 0)::bigint
        FROM public.#{@stream_function}($1)
        """,
        [stream_id]
      )

    explain
  end

  defp aggregate_stream!(stream_id) do
    %{rows: [row]} =
      Repo.query!(
        """
        SELECT count(*)::bigint, COALESCE(sum(pg_column_size(decoded)), 0)::bigint
        FROM public.#{@stream_function}($1)
        """,
        [stream_id]
      )

    row
  end

  defp backend_memory_bytes! do
    %{rows: [[bytes]]} =
      Repo.query!("SELECT COALESCE(sum(total_bytes), 0)::bigint FROM pg_backend_memory_contexts")

    bytes
  end

  defp sum_plan_value(plan, key) do
    Map.get(plan, key, 0) +
      Enum.reduce(Map.get(plan, "Plans", []), 0, fn child, total ->
        total + sum_plan_value(child, key)
      end)
  end

  defp max_plan_value(plan, key) do
    Enum.reduce(Map.get(plan, "Plans", []), Map.get(plan, key, 0), fn child, maximum ->
      max(maximum, max_plan_value(child, key))
    end)
  end

  defp plan_node_types(plan) do
    [
      Map.fetch!(plan, "Node Type")
      | Enum.flat_map(Map.get(plan, "Plans", []), &plan_node_types/1)
    ]
    |> Enum.uniq()
  end

  defp run_latency_benchmarks do
    binaries = List.duplicate(encode_fixed_event!(), 1_000)

    Benchee.run(
      %{
        "BEAM decode / 1000 resident binaries" => fn ->
          Enum.map(binaries, fn data ->
            {:ok, decoded} = OrderCreated.decode(data)
            decoded
          end)
        end,
        "raw DB fetch + BEAM decode / 1000 events" => fn ->
          %{rows: rows} =
            Repo.query!("SELECT data FROM public.#{@raw_stream_function}($1)", ["fixed-1000"])

          Enum.map(rows, fn [data] ->
            {:ok, decoded} = OrderCreated.decode(data)
            decoded
          end)
        end,
        "retrieve selected columns / 1000 events" => fn ->
          Repo.query!("SELECT * FROM public.#{@projected_stream_function}($1)", ["fixed-1000"])
        end,
        "retrieve native typed rows / 1000 events" => fn ->
          Repo.query!("SELECT * FROM public.#{@typed_stream_function}($1)", ["fixed-1000"])
        end,
        "decode fixed stream / 1 event" => fn -> aggregate_stream!("fixed-1") end,
        "decode fixed stream / 100 events" => fn -> aggregate_stream!("fixed-100") end,
        "decode fixed stream / 1000 events" => fn -> aggregate_stream!("fixed-1000") end,
        "decode grouped stream / 100 events" => fn -> aggregate_stream!("grouped-100") end,
        "retrieve decoded stream / 1000 events" => fn ->
          Repo.query!("SELECT * FROM public.#{@stream_function}($1)", ["fixed-1000"])
        end
      },
      time: 2,
      warmup: 1,
      memory_time: 1,
      reduction_time: 1
    )
  end

  defp format_bytes(bytes) when bytes < 1_024, do: "#{bytes} B"
  defp format_bytes(bytes), do: "#{Float.round(bytes / 1_024, 2)} KiB"

  defp format_signed_bytes(bytes) when bytes < 0, do: "-#{format_bytes(abs(bytes))}"
  defp format_signed_bytes(bytes), do: format_bytes(bytes)

  defp cleanup! do
    drop_stream_functions!()
    Repo.query!("DROP TABLE IF EXISTS #{@table}")
  end

  defp drop_stream_functions! do
    for function <- [
          @stream_function,
          @raw_stream_function,
          @projected_stream_function,
          @typed_stream_function
        ] do
      Repo.query!(SQL.drop_stream_decoder_statement(function: "public.#{function}"))
    end
  end
end

SQLDecodeBench.run()
