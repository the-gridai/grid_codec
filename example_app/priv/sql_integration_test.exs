# SQL Integration Test
#
# End-to-end test: encode events → store as bytea → generate SQL → query decoded
#
# Run from example_app/:
#   mix run priv/sql_integration_test.exs

alias ExampleApp.Repo
alias ExampleApp.Events.OrderCreated
alias ExampleApp.Events.TradeExecuted

IO.puts("=== GridCodec SQL Integration Test ===\n")

# ============================================================================
# 1. Create events table (like Commanded's event_store)
# ============================================================================

IO.puts("1. Creating events table...")

Repo.query!("DROP TABLE IF EXISTS gridcodec_test_events")

Repo.query!("""
CREATE TABLE gridcodec_test_events (
  id serial PRIMARY KEY,
  stream_id text NOT NULL,
  event_type text NOT NULL,
  data bytea NOT NULL,
  created_at timestamptz DEFAULT now()
)
""")

# ============================================================================
# 2. Encode and insert events
# ============================================================================

IO.puts("2. Inserting encoded events...")

events = [
  {"market-1", %OrderCreated{
    order_id: <<1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16>>,
    user_id: 42,
    symbol: "BTC/USD",
    side: :buy,
    price: 67_500,
    quantity: 100,
    timestamp: 1_709_000_000_000_000,
    flags: 1
  }},
  {"market-1", %OrderCreated{
    order_id: <<16, 15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1>>,
    user_id: 99,
    symbol: "ETH/USD",
    side: :sell,
    price: 3_400,
    quantity: 50,
    timestamp: 1_709_000_001_000_000,
    flags: 0
  }},
  {"market-1", %OrderCreated{
    order_id: <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 99>>,
    user_id: nil,
    symbol: nil,
    side: nil,
    price: nil,
    quantity: nil,
    timestamp: nil,
    flags: nil
  }},
  {"market-2", %TradeExecuted{
    trade_id: <<2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2>>,
    order_id: <<1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16>>,
    side: :buy,
    price: 67_500,
    quantity: 50,
    timestamp: 1_709_000_002_000_000
  }}
]

for {stream_id, event} <- events do
  {:ok, binary} = event.__struct__.encode(event)
  type_name = event.__struct__.__type__()

  Repo.query!(
    "INSERT INTO gridcodec_test_events (stream_id, event_type, data) VALUES ($1, $2, $3)",
    [stream_id, type_name, binary]
  )
end

IO.puts("   Inserted #{length(events)} events\n")

# ============================================================================
# 3. Generate and install SQL functions
# ============================================================================

IO.puts("3. Generating and installing SQL functions...")

sql = GridCodec.SQL.generate_all([OrderCreated, TradeExecuted])
tmp_path = Path.join(System.tmp_dir!(), "gridcodec_functions.sql")
File.write!(tmp_path, sql)

config = ExampleApp.Repo.config()
db = Keyword.fetch!(config, :database)
user = Keyword.get(config, :username, "postgres")
host = Keyword.get(config, :hostname, "localhost")
port = Keyword.get(config, :port, 5432)

{output, exit_code} =
  System.cmd("psql", ["-h", host, "-p", "#{port}", "-U", user, "-d", db, "-f", tmp_path],
    stderr_to_stdout: true
  )

if exit_code != 0 do
  IO.puts("   psql output:\n#{output}")
  raise "psql failed with exit code #{exit_code}"
end

File.rm!(tmp_path)
IO.puts("   SQL functions installed via psql\n")

# ============================================================================
# 4. Query raw events
# ============================================================================

IO.puts("4. Raw events in table:")

%{rows: rows} =
  Repo.query!("SELECT id, stream_id, event_type, octet_length(data) as bytes FROM gridcodec_test_events")

for [id, stream, type, bytes] <- rows do
  IO.puts("   ##{id} | #{stream} | #{type} | #{bytes} bytes")
end

IO.puts("")

# ============================================================================
# 5. Query with header parser
# ============================================================================

IO.puts("5. Headers parsed:")

%{rows: rows} =
  Repo.query!("""
  SELECT id, event_type, (gridcodec.read_header(data)).*
  FROM gridcodec_test_events
  """)

for [id, type, bl, tid, sid, ver] <- rows do
  IO.puts("   ##{id} | #{type} | block_length=#{bl}, template_id=#{tid}, schema_id=#{sid}, version=#{ver}")
end

IO.puts("")

# ============================================================================
# 6. Query decoded OrderCreated events
# ============================================================================

IO.puts("6. Decoded OrderCreated events:")

%{rows: rows, columns: columns} =
  Repo.query!("""
  SELECT e.id, e.stream_id, d.*
  FROM gridcodec_test_events e,
       gridcodec.decode_ordercreated(e.data) d
  WHERE e.event_type = 'OrderCreated'
  ORDER BY e.id
  """)

IO.puts("   Columns: #{Enum.join(columns, ", ")}")

for row <- rows do
  pairs = Enum.zip(columns, row)
  formatted = Enum.map_join(pairs, " | ", fn {col, val} -> "#{col}=#{inspect(val)}" end)
  IO.puts("   #{formatted}")
end

IO.puts("")

# ============================================================================
# 7. Query with filtering on decoded fields
# ============================================================================

IO.puts("7. Filter: OrderCreated where side='buy' and price > 0:")

%{rows: rows} =
  Repo.query!("""
  SELECT d.order_id, d.side, d.price, d.quantity, d.symbol
  FROM gridcodec_test_events e,
       gridcodec.decode_ordercreated(e.data) d
  WHERE e.event_type = 'OrderCreated'
    AND d.side = 'buy'
    AND d.price > 0
  """)

for [order_id, side, price, qty, symbol] <- rows do
  IO.puts("   #{order_id} | #{side} | price=#{price} | qty=#{qty} | #{symbol}")
end

IO.puts("")

# ============================================================================
# 8. Verify null handling
# ============================================================================

IO.puts("8. Null handling (event #3 has all nil fields except order_id):")

%{rows: [row]} =
  Repo.query!("""
  SELECT d.*
  FROM gridcodec_test_events e,
       gridcodec.decode_ordercreated(e.data) d
  WHERE e.id = 3
  """)

IO.inspect(row, label: "   Row 3")

IO.puts("")

# ============================================================================
# 9. Cleanup
# ============================================================================

IO.puts("9. Cleaning up...")
Repo.query!("DROP TABLE IF EXISTS gridcodec_test_events;")
IO.puts("   Done!\n")

IO.puts("=== All SQL integration tests passed! ===")
