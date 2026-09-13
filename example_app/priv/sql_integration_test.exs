# SQL Integration Test
#
# End-to-end test: encode events → store as bytea → generate SQL → query decoded
#
# Run from example_app/:
#   mix run priv/sql_integration_test.exs

defmodule ExampleApp.SQLIntegrationWideStatus do
  @moduledoc false

  use GridCodec.Types.Enum, encoding: :u16

  defenum do
    value(:pending, 1)
    value(:review, 300)
  end
end

defmodule ExampleApp.SQLIntegrationNumericEntry do
  @moduledoc false

  use GridCodec.Struct, template_id: 90, schema_id: 100

  alias ExampleApp.SQLIntegrationWideStatus

  defcodec do
    field :status, SQLIntegrationWideStatus
    field :amount, {:decimal, scale: 2}, wire_format: :i64
    field :positive_amount, {:positive_decimal, scale: 2}, wire_format: :u64
  end
end

defmodule ExampleApp.SQLIntegrationNumericGroups do
  @moduledoc false

  use GridCodec.Struct, template_id: 91, schema_id: 100

  alias ExampleApp.SQLIntegrationNumericEntry
  alias ExampleApp.SQLIntegrationWideStatus

  defcodec do
    field :event_id, :u64

    group :inline_values do
      field :status, SQLIntegrationWideStatus
      field :amount, {:decimal, scale: 2}, wire_format: :i64
      field :positive_amount, {:positive_decimal, scale: 2}, wire_format: :u64
    end

    group :typed_values, of: SQLIntegrationNumericEntry
  end
end

alias ExampleApp.Events.MarketCreated
alias ExampleApp.Events.OrderCreated
alias ExampleApp.Events.TradeExecuted
alias ExampleApp.Repo
alias ExampleApp.SQL.Catalog
alias ExampleApp.SQLIntegrationNumericEntry
alias ExampleApp.SQLIntegrationNumericGroups
alias ExampleApp.Views.CurrencyAccount
alias ExampleApp.Views.Reservation

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
  stream_version bigint NOT NULL,
  event_type text NOT NULL,
  data bytea NOT NULL,
  created_at timestamptz DEFAULT now(),
  UNIQUE (stream_id, stream_version)
)
""")

Repo.query!("""
CREATE INDEX gridcodec_test_events_stream_idx
  ON gridcodec_test_events (stream_id, stream_version)
""")

# ============================================================================
# 2. Encode and insert events
# ============================================================================

IO.puts("2. Inserting encoded events...")

events = [
  {"market-1", 1,
   %OrderCreated{
     order_id: <<1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16>>,
     user_id: 42,
     symbol: "BTC/USD",
     side: :buy,
     price: 67_500,
     quantity: 100,
     timestamp: 1_709_000_000_000_000,
     flags: 1
   }},
  {"market-1", 2,
   %OrderCreated{
     order_id: <<16, 15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1>>,
     user_id: 99,
     symbol: "ETH/USD",
     side: :sell,
     price: 3_400,
     quantity: 50,
     timestamp: 1_709_000_001_000_000,
     flags: 0
   }},
  {"market-1", 3,
   %OrderCreated{
     order_id: <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 99>>,
     user_id: nil,
     symbol: nil,
     side: nil,
     price: nil,
     quantity: nil,
     timestamp: nil,
     flags: nil
   }},
  {"market-2", 1,
   %TradeExecuted{
     trade_id: <<2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2>>,
     order_id: <<1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16>>,
     side: :buy,
     price: 67_500,
     quantity: 50,
     timestamp: 1_709_000_002_000_000
   }},
  {"account-7", 1,
   %CurrencyAccount{
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
   }},
  {"numeric-1", 1,
   struct(SQLIntegrationNumericGroups,
     event_id: 9001,
     inline_values: [
       %{status: :review, amount: Decimal.new("123.45"), positive_amount: Decimal.new("67.89")}
     ],
     typed_values: [
       struct(SQLIntegrationNumericEntry,
         status: :review,
         amount: Decimal.new("-12.34"),
         positive_amount: Decimal.new("56.78")
       )
     ]
   )},
  {"mixed-1", 1,
   %OrderCreated{
     order_id: <<1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16>>,
     user_id: 42,
     symbol: "BTC/USD",
     side: :buy,
     price: 67_500,
     quantity: 100,
     timestamp: 1_709_000_000_000_000,
     flags: 1
   }},
  {"mixed-1", 2,
   %TradeExecuted{
     trade_id: <<2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2>>,
     order_id: <<1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16>>,
     side: :buy,
     price: 67_500,
     quantity: 50,
     timestamp: 1_709_000_002_000_000
   }},
  {"mixed-1", 3,
   %OrderCreated{
     order_id: <<16, 15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1>>,
     user_id: 99,
     symbol: "ETH/USD",
     side: :sell,
     price: 3_400,
     quantity: 50,
     timestamp: 1_709_000_001_000_000,
     flags: 0
   }},
  {"mixed-1", 4,
   %MarketCreated{
     market_id: <<3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3>>,
     active: true,
     name: "BTC/USD",
     description: "Bitcoin",
     category: "crypto"
   }}
]

for {stream_id, stream_version, event} <- events do
  {:ok, binary} = event.__struct__.encode(event)
  type_name = event.__struct__.__type__()

  Repo.query!(
    """
    INSERT INTO gridcodec_test_events (stream_id, stream_version, event_type, data)
    VALUES ($1, $2, $3, $4)
    """,
    [stream_id, stream_version, type_name, binary]
  )
end

IO.puts("   Inserted #{length(events)} events\n")

# ============================================================================
# 3. Generate and install SQL functions
# ============================================================================

IO.puts("3. Generating and installing SQL functions...")

codec_modules = [
  OrderCreated,
  TradeExecuted,
  CurrencyAccount,
  SQLIntegrationNumericGroups
]

stream_opts = [table: "public.gridcodec_test_events"]

statements =
  GridCodec.SQL.drop_statements(codec_modules) ++
    GridCodec.SQL.generate_all_statements(codec_modules) ++
    Catalog.drop_statements(stream_opts) ++
    Catalog.install_statements(stream_opts)

Enum.each(statements, &Repo.query!(&1))
IO.puts("   SQL functions installed via Ecto\n")

%{rows: [[zero, maximum, minimum, negative_one]]} =
  Repo.query!("""
  SELECT
    gridcodec.read_i64_bigint('\\x0000000000000000'::bytea, 0),
    gridcodec.read_i64_bigint('\\xffffffffffffffff7f'::bytea, 1),
    gridcodec.read_i64_bigint('\\x000000000000000080'::bytea, 1),
    gridcodec.read_i64_bigint('\\xffffffffffffffffff'::bytea, 1)
  """)

unless {zero, maximum, minimum, negative_one} ==
         {0, 9_223_372_036_854_775_807, -9_223_372_036_854_775_808, -1} do
  raise "native signed i64 SQL decoding returned unexpected values"
end

# ============================================================================
# 4. Query raw events
# ============================================================================

IO.puts("4. Raw events in table:")

%{rows: rows} =
  Repo.query!(
    "SELECT id, stream_id, event_type, octet_length(data) as bytes FROM gridcodec_test_events"
  )

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
  IO.puts(
    "   ##{id} | #{type} | block_length=#{bl}, template_id=#{tid}, schema_id=#{sid}, version=#{ver}"
  )
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
# 9. Query a fixed repeating group as JSONB
# ============================================================================

IO.puts("9. Decoded CurrencyAccount reservations:")

%{rows: [[account_id, reservations]]} =
  Repo.query!("""
  SELECT d.account_id, d.reservations
  FROM gridcodec_test_events e,
       gridcodec.decode_exampleapp_views_currencyaccount(e.data) d
  WHERE e.event_type = 'ExampleApp.Views.CurrencyAccount'
  """)

IO.puts("   account_id=#{account_id}")
IO.inspect(reservations, label: "   reservations")

unless length(reservations) == 2 and Enum.at(reservations, 0)["reservation_id"] == 701 do
  raise "fixed-group SQL decoding returned unexpected reservations"
end

IO.puts("")

# ============================================================================
# 10. Decode wide enums and scaled decimal groups
# ============================================================================

IO.puts("10. Decoded wide-enum and scaled-decimal groups:")

%{rows: [[inline_values, typed_values]]} =
  Repo.query!("""
  SELECT d.inline_values, d.typed_values
  FROM gridcodec_test_events e,
       gridcodec.decode_exampleapp_sqlintegrationnumericgroups(e.data) d
  WHERE e.stream_id = 'numeric-1'
  """)

IO.inspect(inline_values, label: "   inline")
IO.inspect(typed_values, label: "   typed")

unless get_in(inline_values, [Access.at(0), "status"]) == "review" and
         get_in(inline_values, [Access.at(0), "amount"]) == 123.45 and
         get_in(inline_values, [Access.at(0), "positive_amount"]) == 67.89 and
         get_in(typed_values, [Access.at(0), "status"]) == "review" and
         get_in(typed_values, [Access.at(0), "amount"]) == -12.34 and
         get_in(typed_values, [Access.at(0), "positive_amount"]) == 56.78 do
  raise "wide-enum or scaled-decimal SQL decoding returned unexpected values"
end

IO.puts("")

# ============================================================================
# 11. Retrieve and decode one complete stream
# ============================================================================

IO.puts("11. Decoded market-1 stream:")

%{rows: stream_rows} =
  Repo.query!(
    """
    SELECT stream_version, event_type, decoded
    FROM #{Catalog.jsonb_stream_function()}($1)
    """,
    ["market-1"]
  )

IO.inspect(stream_rows, label: "   events")

unless Enum.map(stream_rows, &hd/1) == [1, 2, 3] and
         Enum.all?(stream_rows, fn [_version, type, decoded] ->
           type == "OrderCreated" and is_map(decoded)
         end) do
  raise "set-based stream SQL decoding returned unexpected events"
end

%{rows: raw_stream_rows} =
  Repo.query!(
    """
    SELECT stream_version, event_type, data
    FROM #{Catalog.raw_stream_function()}($1)
    """,
    ["market-1"]
  )

unless Enum.map(raw_stream_rows, fn [_version, _type, data] ->
         {:ok, event} = OrderCreated.decode(data)
         event.side
       end) == [:buy, :sell, nil] do
  raise "raw stream reader returned unexpected binaries"
end

%{rows: projected_rows} =
  Repo.query!(
    """
    SELECT stream_version, side, price, quantity
    FROM #{Catalog.projected_stream_function()}($1)
    """,
    ["market-1"]
  )

unless projected_rows == [
         [1, "buy", Decimal.new("67500"), 100],
         [2, "sell", Decimal.new("3400"), 50],
         [3, nil, nil, nil]
       ] do
  raise "fixed-field stream projection returned unexpected rows"
end

%{rows: typed_rows} =
  Repo.query!(
    """
    SELECT
      stream_version,
      event_type,
      order_id,
      user_id::bigint,
      symbol,
      side,
      price::bigint,
      quantity,
      timestamp,
      flags
    FROM #{Catalog.typed_stream_function()}($1)
    """,
    ["market-1"]
  )

unless [
         [
           1,
           "OrderCreated",
           _,
           42,
           "BTC/USD",
           "buy",
           67_500,
           100,
           %DateTime{},
           1
         ],
         [
           2,
           "OrderCreated",
           _,
           99,
           "ETH/USD",
           "sell",
           3_400,
           50,
           %DateTime{},
           0
         ],
         [3, "OrderCreated", _, nil, nil, nil, nil, nil, nil, nil]
       ] = typed_rows do
  raise "native typed stream projection returned unexpected rows"
end

%{rows: mixed_rows} =
  Repo.query!(
    """
    SELECT stream_version, event_type
    FROM #{Catalog.mixed_stream_function()}($1)
    """,
    ["mixed-1"]
  )

unless mixed_rows == [
         [1, "OrderCreated"],
         [2, "TradeExecuted"],
         [3, "OrderCreated"]
       ] do
  raise "mixed-type stream reader returned unexpected events"
end

%{rows: mixed_page} =
  Repo.query!(
    """
    SELECT stream_version, event_type
    FROM #{Catalog.mixed_stream_function()}($1, $2, $3)
    """,
    ["mixed-1", 2, 1]
  )

unless mixed_page == [[2, "TradeExecuted"]] do
  raise "mixed-type stream page returned unexpected events"
end

%{rows: skipped_page} =
  Repo.query!(
    """
    SELECT stream_version
    FROM #{Catalog.mixed_stream_function()}($1, $2, $3)
    """,
    ["mixed-1", 4, 10]
  )

unless skipped_page == [] do
  raise "mixed-type stream page should skip unmatched types"
end

%{rows: [[stream_max]]} =
  Repo.query!(
    """
    SELECT #{Catalog.mixed_stream_version_function()}($1)
    """,
    ["mixed-1"]
  )

unless stream_max == 4 do
  raise "unfiltered stream version should include unmatched types"
end

IO.puts("")

# ============================================================================
# 12. Cleanup
# ============================================================================

IO.puts("12. Cleaning up...")

Enum.each(Catalog.drop_statements(stream_opts), &Repo.query!(&1))
Repo.query!("DROP TABLE IF EXISTS gridcodec_test_events;")
IO.puts("   Done!\n")

IO.puts("=== All SQL integration tests passed! ===")
