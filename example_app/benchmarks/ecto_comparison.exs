# Ecto vs GridCodec Comparison Benchmark
#
# Compares construction, validation, and serialization pipelines:
#   GridCodec new/1 vs Ecto.Changeset on embedded schemas
#   GridCodec encode/1 vs Jason.encode on Ecto structs
#   GridCodec new_binary/1 vs Ecto changeset + Jason encode
#
# Run from example_app/:
#   mix run benchmarks/ecto_comparison.exs

defmodule Bench.EctoOrder do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :order_id, :binary
    field :user_id, :integer
    field :symbol, :string
    field :side, Ecto.Enum, values: [:buy, :sell]
    field :price, :integer
    field :quantity, :integer
    field :timestamp, :integer
    field :flags, :integer
  end

  @fields ~w(order_id user_id symbol side price quantity timestamp flags)a

  def new(attrs) do
    %__MODULE__{}
    |> cast(attrs, @fields)
    |> validate_required(@fields)
    |> apply_action(:insert)
  end

  def new_json(attrs) do
    case new(attrs) do
      {:ok, struct} ->
        json_map =
          struct
          |> Map.from_struct()
          |> Map.update!(:order_id, &Base.encode16(&1, case: :lower))

        {:ok, Jason.encode!(json_map)}

      error ->
        error
    end
  end
end

alias ExampleApp.Events.OrderCreated

order_id = :crypto.strong_rand_bytes(16)
ts = System.system_time(:microsecond)

typed_attrs = %{
  order_id: order_id,
  user_id: 123_456_789,
  symbol: "BTC/USD",
  side: :buy,
  price: 67_500_00,
  quantity: 1_000,
  timestamp: ts,
  flags: 3
}

string_attrs = %{
  "order_id" => order_id,
  "user_id" => 123_456_789,
  "symbol" => "BTC/USD",
  "side" => "buy",
  "price" => 67_500_00,
  "quantity" => 1_000,
  "timestamp" => ts,
  "flags" => 3
}

# Pre-construct for encode-only benchmarks
{:ok, gc_struct} = OrderCreated.new(typed_attrs)
{:ok, ecto_struct} = Bench.EctoOrder.new(typed_attrs)
{:ok, gc_binary} = OrderCreated.encode(gc_struct)

ecto_json_map =
  ecto_struct
  |> Map.from_struct()
  |> Map.update!(:order_id, &Base.encode16(&1, case: :lower))

ecto_json = Jason.encode!(ecto_json_map)

IO.puts("""

=== Sizes ===
  GridCodec binary: #{byte_size(gc_binary)} bytes
  Ecto → JSON:      #{byte_size(ecto_json)} bytes
  Ratio:            #{Float.round(byte_size(ecto_json) / byte_size(gc_binary), 1)}x larger
""")

# ---------------------------------------------------------------------------
# 1. Construction: new/1 vs changeset
# ---------------------------------------------------------------------------

IO.puts("=== Construction (typed attrs) ===\n")

Benchee.run(
  %{
    "GridCodec.new/1" => fn -> {:ok, _} = OrderCreated.new(typed_attrs) end,
    "Ecto changeset + apply_action" => fn -> {:ok, _} = Bench.EctoOrder.new(typed_attrs) end
  },
  warmup: 2,
  time: 5,
  memory_time: 1,
  print: [configuration: false]
)

IO.puts("\n=== Construction (string keys) ===\n")

Benchee.run(
  %{
    "GridCodec.new/1 (string keys)" => fn -> {:ok, _} = OrderCreated.new(string_attrs) end,
    "Ecto changeset (string keys)" => fn -> {:ok, _} = Bench.EctoOrder.new(string_attrs) end
  },
  warmup: 2,
  time: 5,
  memory_time: 1,
  print: [configuration: false]
)

# ---------------------------------------------------------------------------
# 2. Encode: encode/1 vs Jason.encode
# ---------------------------------------------------------------------------

IO.puts("\n=== Encode (struct → wire format) ===\n")

Benchee.run(
  %{
    "GridCodec.encode/1 → binary" => fn -> {:ok, _} = OrderCreated.encode(gc_struct) end,
    "Jason.encode! (Ecto struct)" => fn -> Jason.encode!(ecto_json_map) end
  },
  warmup: 2,
  time: 5,
  memory_time: 1,
  print: [configuration: false]
)

# ---------------------------------------------------------------------------
# 3. Decode: decode/1 vs Jason.decode
# ---------------------------------------------------------------------------

IO.puts("\n=== Decode (wire format → struct) ===\n")

Benchee.run(
  %{
    "GridCodec.decode/1 → struct" => fn -> {:ok, _} = OrderCreated.decode(gc_binary) end,
    "Jason.decode! → map" => fn -> Jason.decode!(ecto_json) end
  },
  warmup: 2,
  time: 5,
  memory_time: 1,
  print: [configuration: false]
)

# ---------------------------------------------------------------------------
# 4. Full pipeline: attrs → wire format
# ---------------------------------------------------------------------------

IO.puts("\n=== Full Pipeline (attrs → wire format) ===\n")

Benchee.run(
  %{
    "GridCodec.new_binary/1" => fn ->
      {:ok, _} = OrderCreated.new_binary(typed_attrs)
    end,
    "GridCodec new/1 + encode/1" => fn ->
      {:ok, s} = OrderCreated.new(typed_attrs)
      {:ok, _} = OrderCreated.encode(s)
    end,
    "Ecto changeset + Jason.encode" => fn ->
      {:ok, _} = Bench.EctoOrder.new_json(typed_attrs)
    end
  },
  warmup: 2,
  time: 5,
  memory_time: 1,
  print: [configuration: false]
)

# ---------------------------------------------------------------------------
# 5. Single field access
# ---------------------------------------------------------------------------

IO.puts("\n=== Single Field Access (:price) ===\n")

require OrderCreated

Benchee.run(
  %{
    "GridCodec.get/2 (zero-copy)" => fn -> OrderCreated.get(gc_binary, :price) end,
    "Map.get on decoded map" => fn ->
      m = Jason.decode!(ecto_json)
      m["price"]
    end,
    "Struct field access (pre-decoded)" => fn -> gc_struct.price end
  },
  warmup: 2,
  time: 5,
  memory_time: 1,
  print: [configuration: false]
)
