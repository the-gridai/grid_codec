defmodule GridCodec.GroupTest do
  use ExUnit.Case
  use ExUnitProperties

  alias GridCodec.Group
  alias GridCodec.Generators

  def encode_entry(%{price: price, qty: qty}) do
    <<price::little-64, qty::little-32>>
  end

  def decode_entry(<<price::little-64, qty::little-32>>) do
    {:ok, %{price: price, qty: qty}}
  end

  describe "encode/2" do
    test "encodes empty list" do
      binary = Group.encode([], &encode_entry/1)
      # Header: blockLength (u16), numInGroup (u16) - both 0
      assert binary == <<0::little-16, 0::little-16>>
    end

    test "encodes single entry" do
      entries = [%{price: 100, qty: 10}]
      binary = Group.encode(entries, &encode_entry/1)

      # Header: blockLength (u16), numInGroup (u16)
      assert <<12::little-16, 1::little-16, entry::binary>> = binary
      assert entry == <<100::little-64, 10::little-32>>
    end

    test "encodes multiple entries" do
      entries = [
        %{price: 100, qty: 10},
        %{price: 200, qty: 20},
        %{price: 300, qty: 30}
      ]

      binary = Group.encode(entries, &encode_entry/1)

      # Header: blockLength (u16), numInGroup (u16)
      assert <<12::little-16, 3::little-16, rest::binary>> = binary

      # Entries
      assert byte_size(rest) == 3 * 12
    end

    test "raises on inconsistent entry sizes" do
      entries = [%{price: 100, qty: 10}]

      assert_raise ArgumentError, ~r/same size/, fn ->
        Group.encode(entries, fn _ -> <<1, 2, 3>> end)
        |> then(fn _ ->
          # Force evaluation with second entry of different size
          Group.encode([%{price: 100, qty: 10}, %{price: 200, qty: 20}], fn
            %{price: 100} -> <<1, 2, 3>>
            _ -> <<1, 2, 3, 4, 5>>
          end)
        end)
      end
    end
  end

  describe "parse/3" do
    test "parses empty group" do
      binary = <<0::little-32, 0::little-32>>
      {:ok, group} = Group.parse(binary, &decode_entry/1)

      assert Group.count(group) == 0
    end

    test "parses group with entries" do
      entries = [%{price: 100, qty: 10}, %{price: 200, qty: 20}]
      binary = Group.encode(entries, &encode_entry/1)

      {:ok, group} = Group.parse(binary, &decode_entry/1)

      assert Group.count(group) == 2
      assert Group.block_length(group) == 12
    end

    test "returns error on insufficient header" do
      binary = <<0, 1, 2>>
      {:error, reason} = Group.parse(binary, &decode_entry/1)

      assert {:insufficient_header, 3, 4} = reason
    end

    test "returns error on insufficient data" do
      # Header: blockLength=12, numInGroup=10, but no data
      binary = <<12::little-16, 10::little-16>>
      {:error, reason} = Group.parse(binary, &decode_entry/1)

      assert {:insufficient_data, 0, 120} = reason
    end

    test "returns error when max_entries exceeded" do
      # u16 max is 65535, but we limit to 100
      data = :binary.copy(<<0>>, 12 * 1000)
      binary = <<12::little-16, 1000::little-16, data::binary>>
      {:error, reason} = Group.parse(binary, &decode_entry/1, max_entries: 100)

      assert {:max_entries_exceeded, 1000, 100} = reason
    end

    test "returns error when max_bytes exceeded" do
      entries = for i <- 1..1000, do: %{price: i, qty: i}
      binary = Group.encode(entries, &encode_entry/1)

      {:error, reason} = Group.parse(binary, &decode_entry/1, max_bytes: 100)

      assert {:max_bytes_exceeded, _, 100} = reason
    end
  end

  describe "get_entry/2" do
    test "returns entry at index" do
      entries = [%{price: 100, qty: 10}, %{price: 200, qty: 20}]
      binary = Group.encode(entries, &encode_entry/1)
      {:ok, group} = Group.parse(binary, &decode_entry/1)

      assert {:ok, %{price: 100, qty: 10}} = Group.get_entry(group, 0)
      assert {:ok, %{price: 200, qty: 20}} = Group.get_entry(group, 1)
    end

    test "returns error for out of bounds index" do
      entries = [%{price: 100, qty: 10}]
      binary = Group.encode(entries, &encode_entry/1)
      {:ok, group} = Group.parse(binary, &decode_entry/1)

      assert {:error, {:index_out_of_bounds, 1, 1}} = Group.get_entry(group, 1)
      assert {:error, {:index_out_of_bounds, -1, 1}} = Group.get_entry(group, -1)
    end
  end

  describe "get_field/3" do
    test "returns field from entry at index" do
      entries = [%{price: 100, qty: 10}, %{price: 200, qty: 20}]
      binary = Group.encode(entries, &encode_entry/1)
      {:ok, group} = Group.parse(binary, &decode_entry/1)

      assert {:ok, 100} = Group.get_field(group, 0, :price)
      assert {:ok, 20} = Group.get_field(group, 1, :qty)
    end

    test "returns error for unknown field" do
      entries = [%{price: 100, qty: 10}]
      binary = Group.encode(entries, &encode_entry/1)
      {:ok, group} = Group.parse(binary, &decode_entry/1)

      assert {:error, {:unknown_field, :nonexistent}} = Group.get_field(group, 0, :nonexistent)
    end
  end

  describe "iteration" do
    test "stream/1 returns lazy enumerable" do
      entries = for i <- 1..100, do: %{price: i * 100, qty: i}
      binary = Group.encode(entries, &encode_entry/1)
      {:ok, group} = Group.parse(binary, &decode_entry/1)

      # Take first 5
      first_five =
        group
        |> Group.stream()
        |> Enum.take(5)

      assert length(first_five) == 5
      assert Enum.at(first_five, 0) == %{price: 100, qty: 1}
      assert Enum.at(first_five, 4) == %{price: 500, qty: 5}
    end

    test "map/2 transforms entries" do
      entries = [%{price: 100, qty: 10}, %{price: 200, qty: 20}]
      binary = Group.encode(entries, &encode_entry/1)
      {:ok, group} = Group.parse(binary, &decode_entry/1)

      prices = Group.map(group, fn e -> e.price end)
      assert prices == [100, 200]
    end

    test "reduce/3 accumulates" do
      entries = [%{price: 100, qty: 10}, %{price: 200, qty: 20}]
      binary = Group.encode(entries, &encode_entry/1)
      {:ok, group} = Group.parse(binary, &decode_entry/1)

      total_qty = Group.reduce(group, 0, fn e, acc -> acc + e.qty end)
      assert total_qty == 30
    end

    test "to_list/1 decodes all entries" do
      entries = [%{price: 100, qty: 10}, %{price: 200, qty: 20}]
      binary = Group.encode(entries, &encode_entry/1)
      {:ok, group} = Group.parse(binary, &decode_entry/1)

      list = Group.to_list(group)
      assert list == entries
    end
  end

  describe "utilities" do
    test "total_size/1 returns total group size" do
      entries = [%{price: 100, qty: 10}, %{price: 200, qty: 20}]
      binary = Group.encode(entries, &encode_entry/1)
      {:ok, group} = Group.parse(binary, &decode_entry/1)

      # Header (4) + 2 entries × 12 bytes
      assert Group.total_size(group) == 4 + 2 * 12
    end

    test "rest/1 returns remaining binary" do
      entries = [%{price: 100, qty: 10}]
      group_binary = Group.encode(entries, &encode_entry/1)
      extra_data = "extra"
      binary = <<group_binary::binary, extra_data::binary>>

      {:ok, group} = Group.parse(binary, &decode_entry/1)
      assert Group.rest(group) == "extra"
    end

    test "header_size/0 returns 4" do
      assert Group.header_size() == 4
    end

    test "max_entries/0 returns u16 max" do
      assert Group.max_entries() == 65_535
    end

    test "max_entry_size/0 returns u16 max" do
      assert Group.max_entry_size() == 65_535
    end
  end

  # ============================================================================
  # Property-Based Tests
  # ============================================================================

  describe "property: group roundtrip" do
    property "encode/decode roundtrip preserves data" do
      entry_gen =
        StreamData.fixed_map(%{
          price: Generators.u64(),
          qty: Generators.u32()
        })

      check all(
              entries <- StreamData.list_of(entry_gen, min_length: 0, max_length: 100),
              max_runs: 50
            ) do
        binary = Group.encode(entries, &encode_entry/1)
        {:ok, group} = Group.parse(binary, &decode_entry/1)

        assert Group.count(group) == length(entries)
        assert Group.to_list(group) == entries
      end
    end

    property "random access matches iteration" do
      entry_gen =
        StreamData.fixed_map(%{
          price: Generators.u64(),
          qty: Generators.u32()
        })

      check all(
              entries <- StreamData.list_of(entry_gen, min_length: 1, max_length: 50),
              max_runs: 30
            ) do
        binary = Group.encode(entries, &encode_entry/1)
        {:ok, group} = Group.parse(binary, &decode_entry/1)

        # Random access should match iteration
        for {expected, idx} <- Enum.with_index(entries) do
          {:ok, actual} = Group.get_entry(group, idx)
          assert actual == expected
        end
      end
    end
  end
end
