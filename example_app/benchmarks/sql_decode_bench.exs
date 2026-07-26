# PostgreSQL decoder and indexed stream-query benchmark
#
# Run from example_app/:
#   DATABASE_HOST=db MIX_ENV=prod mix run benchmarks/sql_decode_bench.exs
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

  def run do
    Logger.configure(level: :warning)
    setup!()

    try do
      print_database_report()
      run_latency_benchmarks()
    after
      cleanup!()
    end
  end

  defp setup! do
    Repo.query!("DROP FUNCTION IF EXISTS public.#{@stream_function}(text)")
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
      insert_stream!("fixed-#{size}", size, OrderCreated.__type__(), fixed_binary)
    end

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
    Benchee.run(
      %{
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
      memory_time: 0
    )
  end

  defp format_bytes(bytes) when bytes < 1_024, do: "#{bytes} B"
  defp format_bytes(bytes), do: "#{Float.round(bytes / 1_024, 2)} KiB"

  defp format_signed_bytes(bytes) when bytes < 0, do: "-#{format_bytes(abs(bytes))}"
  defp format_signed_bytes(bytes), do: format_bytes(bytes)

  defp cleanup! do
    Repo.query!("DROP FUNCTION IF EXISTS public.#{@stream_function}(text)")
    Repo.query!("DROP TABLE IF EXISTS #{@table}")
  end
end

SQLDecodeBench.run()
