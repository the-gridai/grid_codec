defmodule GridCodec.BatchDslTest do
  use ExUnit.Case, async: true

  alias GridCodec.TestSupport.Batch.LargeCommand
  alias GridCodec.TestSupport.Batch.MediumCommand
  alias GridCodec.TestSupport.Batch.SmallCommand

  defmodule MarketCommands do
    use GridCodec.Struct, template_id: 750, schema_id: 70, version: 1

    defcodec do
      field :market_id, :uuid

      batch(:commands,
        any_of: [
          GridCodec.TestSupport.Batch.SmallCommand,
          GridCodec.TestSupport.Batch.MediumCommand,
          GridCodec.TestSupport.Batch.LargeCommand
        ]
      )
    end
  end

  defp make_small(id), do: %SmallCommand{order_id: id, timestamp: 1_000_000}

  defp make_medium(id),
    do: %MediumCommand{
      order_id: id,
      user_id: 42,
      symbol: <<1::128>>,
      price: 10_000,
      quantity: 100,
      flags: 0
    }

  defp make_large(id),
    do: %LargeCommand{
      order_id: id,
      user_id: 42,
      symbol: <<2::128>>,
      price: 10_000,
      quantity: 500,
      limit_price: 10_050,
      stop_price: 9_950,
      flags: 1,
      side: 0,
      order_type: 1,
      time_in_force: 2,
      reserved: 0,
      timestamp: 1_000_000
    }

  defp strip(entry) when is_struct(entry), do: Map.from_struct(entry)
  defp strip(entry) when is_map(entry), do: entry

  describe "DSL integration" do
    test "struct is created with commands field" do
      cmd = %MarketCommands{}
      assert cmd.commands == []
      assert cmd.market_id == nil
    end

    test "encode and decode roundtrip" do
      entries = [make_large(1), make_medium(2), make_small(3)]

      original = %MarketCommands{
        market_id: <<42::128>>,
        commands: entries
      }

      {:ok, binary} = MarketCommands.encode(original)
      {:ok, decoded} = MarketCommands.decode(binary)

      assert decoded.market_id == <<42::128>>
      assert %GridCodec.Batch{} = decoded.commands
      assert GridCodec.Batch.count(decoded.commands) == 3
    end

    test "batch entries decode with correct types and order" do
      entries = [make_large(1), make_medium(2), make_small(3), make_large(4)]

      original = %MarketCommands{
        market_id: <<0::128>>,
        commands: entries
      }

      {:ok, binary} = MarketCommands.encode(original)
      {:ok, decoded} = MarketCommands.decode(binary)

      result = GridCodec.Batch.to_list(decoded.commands)
      assert length(result) == 4

      [{0, 2, d0}, {1, 1, d1}, {2, 0, d2}, {3, 2, d3}] = result

      assert strip(d0) == strip(make_large(1))
      assert strip(d1) == strip(make_medium(2))
      assert strip(d2) == strip(make_small(3))
      assert strip(d3) == strip(make_large(4))
    end

    test "O(1) random access via get/2" do
      entries = [make_small(10), make_medium(20), make_large(30)]

      original = %MarketCommands{market_id: <<0::128>>, commands: entries}
      {:ok, binary} = MarketCommands.encode(original)
      {:ok, decoded} = MarketCommands.decode(binary)

      {:ok, {0, 0, d0}} = GridCodec.Batch.get(decoded.commands, 0)
      {:ok, {1, 1, d1}} = GridCodec.Batch.get(decoded.commands, 1)
      {:ok, {2, 2, d2}} = GridCodec.Batch.get(decoded.commands, 2)

      assert strip(d0) == strip(make_small(10))
      assert strip(d1) == strip(make_medium(20))
      assert strip(d2) == strip(make_large(30))
    end

    test "by_type filters entries" do
      entries = [make_large(1), make_small(2), make_large(3), make_medium(4), make_small(5)]

      original = %MarketCommands{market_id: <<0::128>>, commands: entries}
      {:ok, binary} = MarketCommands.encode(original)
      {:ok, decoded} = MarketCommands.decode(binary)

      smalls = GridCodec.Batch.by_type(decoded.commands, SmallCommand)
      assert length(smalls) == 2

      larges = GridCodec.Batch.by_type(decoded.commands, LargeCommand)
      assert length(larges) == 2

      mediums = GridCodec.Batch.by_type(decoded.commands, MediumCommand)
      assert length(mediums) == 1
    end

    test "stream is lazy" do
      entries =
        Enum.map(0..99, fn i ->
          case rem(i, 3) do
            0 -> make_large(i)
            1 -> make_medium(i)
            2 -> make_small(i)
          end
        end)

      original = %MarketCommands{market_id: <<0::128>>, commands: entries}
      {:ok, binary} = MarketCommands.encode(original)
      {:ok, decoded} = MarketCommands.decode(binary)

      first_5 = decoded.commands |> GridCodec.Batch.stream() |> Enum.take(5)
      assert length(first_5) == 5

      seqs = Enum.map(first_5, fn {seq, _, _} -> seq end)
      assert seqs == [0, 1, 2, 3, 4]
    end

    test "empty batch roundtrip" do
      original = %MarketCommands{market_id: <<0::128>>, commands: []}
      {:ok, binary} = MarketCommands.encode(original)
      {:ok, decoded} = MarketCommands.decode(binary)

      assert %GridCodec.Batch{} = decoded.commands
      assert GridCodec.Batch.count(decoded.commands) == 0
      assert GridCodec.Batch.to_list(decoded.commands) == []
    end

    test "header: false roundtrip" do
      entries = [make_large(1), make_small(2)]
      original = %MarketCommands{market_id: <<0::128>>, commands: entries}

      {:ok, with_header} = MarketCommands.encode(original)
      {:ok, without_header} = MarketCommands.encode(original, header: false)

      assert byte_size(without_header) == byte_size(with_header) - 8

      {:ok, decoded} = MarketCommands.decode(without_header, header: false)
      assert GridCodec.Batch.count(decoded.commands) == 2
    end
  end
end
