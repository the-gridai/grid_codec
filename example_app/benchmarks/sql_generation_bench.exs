# PostgreSQL SQL-generation benchmark
#
# Run from example_app/:
#   MIX_ENV=prod mix run --no-start benchmarks/sql_generation_bench.exs

alias ExampleApp.Events.OrderCreated
alias ExampleApp.Events.TradeExecuted
alias ExampleApp.Views.CurrencyAccount
alias GridCodec.SQL

fixed_codec = OrderCreated
group_codec = CurrencyAccount
catalog = [OrderCreated, TradeExecuted, CurrencyAccount]

fixed_sql = SQL.generate(fixed_codec)
group_sql = SQL.generate(group_codec)
catalog_sql = SQL.generate_all(catalog)

IO.puts("""
GridCodec PostgreSQL generation benchmark
  fixed decoder: #{byte_size(fixed_sql)} bytes
  grouped decoder: #{byte_size(group_sql)} bytes
  three-codec catalog: #{byte_size(catalog_sql)} bytes
""")

Benchee.run(
  %{
    "generate fixed codec" => fn -> SQL.generate(fixed_codec) end,
    "generate codec with fixed group" => fn -> SQL.generate(group_codec) end,
    "generate three-codec catalog" => fn -> SQL.generate_all(catalog) end
  },
  time: 2,
  warmup: 1,
  memory_time: 1,
  reduction_time: 1
)
